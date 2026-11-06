// Asuka Pet network helper (DeepSeek API)
// Usage: node net.js <request.json> <response.json>
// Runs the HTTP calls with Node's OpenSSL TLS stack; PowerShell writes/reads the files.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'

const [reqFile, respFile] = process.argv.slice(2)

function writeOut(obj) {
  mkdirSync(dirname(respFile), { recursive: true })
  writeFileSync(respFile, JSON.stringify(obj), 'utf8')
}

function die(message) {
  writeOut({ ok: false, error: String(message ?? 'unknown error') })
  process.exit(0)
}

function readToken() {
  const home = process.env.DSH_HOME || join(homedir(), '.dsh')
  const file = join(home, '.credentials.yaml')
  const yaml = readFileSync(file, 'utf8')
  const m = yaml.match(/deepseek-account-platform\/default:[\s\S]*?token:\s*([^\s]+)/)
  if (!m) throw new Error('没有找到 DSH 登录凭据，请先在 DeepSeek Harness 里登录 DeepSeek 账号')
  return m[1]
}

async function queryBalance() {
  const token = readToken()
  const res = await fetch('https://platform.deepseek.com/api/v0/users/get_user_summary', {
    headers: { 'x-dsh-auth-token': token, accept: 'application/json' },
    signal: AbortSignal.timeout(20000),
  })
  if (!res.ok) throw new Error('余额接口 HTTP ' + res.status)
  const json = await res.json()
  if (json?.code !== 0) throw new Error('余额接口返回异常: ' + (json?.msg || json?.code))
  const data = json?.data?.biz_data ?? {}
  writeOut({
    ok: true,
    kind: 'balance',
    normal: data.normal_wallets ?? [],
    bonus: data.bonus_wallets ?? [],
    costs: (data.total_costs ?? []).map((w) => ({ currency: w.currency, balance: w.amount ?? w.balance ?? '0' })),
  })
}

async function chat(req) {
  const token = readToken()
  const model = typeof req.model === 'string' && req.model.trim() !== '' ? req.model.trim() : 'deepseek-chat'
  const messages = Array.isArray(req.messages) ? req.messages : []
  const res = await fetch('https://api.deepseek.com/chat/completions', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-dsh-auth-token': token },
    body: JSON.stringify({ model, messages, temperature: 1.0, max_tokens: 400, stream: false }),
    signal: AbortSignal.timeout(40000),
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error('聊天接口 HTTP ' + res.status + ' ' + body.slice(0, 180))
  }
  const json = await res.json()
  let text = json?.choices?.[0]?.message?.content ?? ''
  if (typeof text !== 'string') text = ''
  text = text.trim()
  if (text === '') text = json?.choices?.[0]?.message?.reasoning_content?.trim() ?? ''
  writeOut({ ok: true, kind: 'chat', text })
}

try {
  const req = JSON.parse(readFileSync(reqFile, 'utf8').replace(/^\uFEFF/, ''))
  if (req.kind === 'balance') await queryBalance()
  else if (req.kind === 'chat') await chat(req)
  else die('未知请求类型: ' + String(req.kind))
} catch (error) {
  die(error && error.message ? error.message : error)
}
