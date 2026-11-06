/**
 * dsh-asuka-pet-bridge — DeepSeek Harness 权限请求 ↔ 明日香桌宠 桥接插件。
 *
 * 工作方式：
 *  - 作为 `approval/request` waterfall 的最前置监听器（prepend）挂载；
 *  - 收到请求时先看桌宠是否在线：桌宠每 300ms 写一次 mailbox/heartbeat.json，
 *    文件 12 秒内更新过就算在线；
 *  - 在线：把请求写进 mailbox/requests/<id>.json，等用户在桌宠气泡上点按钮，
 *    桌宠把决定写进 mailbox/decisions/<id>.json；
 *  - 离线或超时（默认 75 秒）：调用 next()，交还给 Harness 自带的 Web 审批卡片。
 *
 * 只做一次性的「允许 / 拒绝」，不改变任何策略设置。
 */

import { existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'
import { randomUUID } from 'node:crypto'

export const name = 'dsh-asuka-pet-bridge'

const DEFAULT_TIMEOUT_MS = 75_000
const HEARTBEAT_FRESH_MS = 12_000

/** 解析桌宠邮箱目录：插件 config.mailboxDir 优先，否则用桌面上的默认安装位置。 */
function resolveMailbox(config) {
  if (config && typeof config.mailboxDir === 'string' && config.mailboxDir.trim() !== '') {
    return config.mailboxDir.trim()
  }
  const home = process.env.USERPROFILE || process.env.HOME || homedir()
  return join(home, 'Desktop', 'asuka-desktop-pet', 'pet', 'data', 'mailbox')
}

function writeJson(file, value) {
  try {
    writeFileSync(file, JSON.stringify(value), 'utf8')
    return true
  } catch {
    return false
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function petAlive(heartbeatFile) {
  try {
    return Date.now() - statSync(heartbeatFile).mtimeMs < HEARTBEAT_FRESH_MS
  } catch {
    return false
  }
}

/** 等待桌宠写决定；signal 中止返回 cancelled，超时返回 timeout。 */
async function waitDecision(decisionFile, signal, timeoutMs) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    if (signal && signal.aborted === true) return 'cancelled'
    if (existsSync(decisionFile)) {
      let decision = ''
      try {
        decision = String(JSON.parse(readFileSync(decisionFile, 'utf8')).decision ?? '')
      } catch {
        decision = ''
      }
      if (decision === 'allow') return 'allowed-once'
      if (decision === 'deny') return 'rejected'
      if (decision === 'cancel') return 'cancelled'
    }
    await sleep(150)
  }
  return 'timeout'
}

export function apply(ctx, config) {
  const timeoutMs = Number(config?.timeoutMs) > 1000 ? Number(config.timeoutMs) : DEFAULT_TIMEOUT_MS
  const mailbox = resolveMailbox(config)
  const requestDir = join(mailbox, 'requests')
  const decisionDir = join(mailbox, 'decisions')
  const heartbeatFile = join(mailbox, 'heartbeat.json')
  const statusFile = join(mailbox, 'bridge-status.json')

  try {
    mkdirSync(requestDir, { recursive: true })
    mkdirSync(decisionDir, { recursive: true })
  } catch {
    // 邮箱建不出来时保持静默，listener 会退化为 next()
  }

  const writeStatus = () => {
    writeJson(statusFile, { ts: Date.now(), pid: process.pid, timeoutMs, mailbox })
  }
  writeStatus()
  const statusTimer = setInterval(writeStatus, 15_000)

  ctx.on(
    'approval/request',
    async (request, next) => {
      if (!petAlive(heartbeatFile)) return await next()
      if (request?.signal?.aborted === true) return 'cancelled'

      const id = randomUUID()
      const requestFile = join(requestDir, id + '.json')
      const decisionFile = join(decisionDir, id + '.json')
      const payload = {
        id,
        ts: Date.now(),
        toolName: typeof request?.toolName === 'string' ? request.toolName : String(request?.toolName ?? ''),
        reason: typeof request?.reason === 'string' ? request.reason : '',
        displayReason: typeof request?.displayReason === 'string' ? request.displayReason : '',
        callId: request?.callId ?? null,
        sessionId: request?.agent?.session?.id ?? null,
      }
      if (!writeJson(requestFile, payload)) return await next()

      try {
        const outcome = await waitDecision(decisionFile, request?.signal, timeoutMs)
        if (outcome === 'timeout') return await next()
        return outcome
      } catch {
        return await next()
      } finally {
        try {
          rmSync(requestFile, { force: true })
        } catch {
          // noop
        }
        try {
          rmSync(decisionFile, { force: true })
        } catch {
          // noop
        }
      }
    },
    { prepend: true },
  )

  return () => {
    clearInterval(statusTimer)
  }
}
