// dsh 容器入口反代：0.0.0.0:3080 -> 127.0.0.1:3081
// 默认行为与纯 TCP 转发等价（原样透传所有头，含 websocket）。
// 当 DSH_ALLOW_REMOTE_SETTINGS=1 且请求 Host 命中 DSH_TRUSTED_HOSTS 白名单时，
// 对 /api/settings.* 与 /api/credentials.*（上游 loopback-only 域）把 Host/Origin
// 改写为 127.0.0.1，使远程浏览器可以配置 LLM providers / 密钥。
// 注意：这是对上游安全设计的显式放宽，仅应在可信网络内开启。
import http from 'node:http'
import net from 'node:net'

const UPSTREAM = { host: '127.0.0.1', port: 3081 }
const ALLOW_REMOTE = process.env.DSH_ALLOW_REMOTE_SETTINGS === '1'
const TRUSTED = (process.env.DSH_TRUSTED_HOSTS || '').split(/\s+/).filter(Boolean)

function splitHostPort(s) {
  if (s.startsWith('[')) {
    const i = s.indexOf(']')
    return [s.slice(0, i + 1), i + 1 < s.length && s[i + 1] === ':' ? s.slice(i + 2) : '']
  }
  const i = s.lastIndexOf(':')
  return i === -1 ? [s, ''] : [s.slice(0, i), s.slice(i + 1)]
}

// 与上游 trustedHosts 语义一致：带端口条目精确匹配 host:port；无端口条目匹配该主机任意端口
function isTrusted(hostHeader) {
  const h = (hostHeader || '').toLowerCase()
  if (!h) return false
  const [name, port] = splitHostPort(h)
  return TRUSTED.some((entry) => {
    const e = entry.toLowerCase()
    const [en, ep] = splitHostPort(e)
    return ep ? e === h : en === name
  })
}

// 仅 settings/credentials 域需要改写（loopback-only 方法都在这些域）
const REWRITE_RE = /^\/api\/(settings|credentials)\./

const server = http.createServer((req, res) => {
  const rewrite = ALLOW_REMOTE && isTrusted(req.headers.host) && REWRITE_RE.test(req.url || '')
  const headers = { ...req.headers }
  if (rewrite) {
    headers.host = '127.0.0.1'
    if (headers.origin) headers.origin = 'http://127.0.0.1'
  }
  const proxy = http.request(
    { host: UPSTREAM.host, port: UPSTREAM.port, method: req.method, path: req.url, headers },
    (pres) => {
      res.writeHead(pres.statusCode, pres.headers)
      pres.pipe(res)
    },
  )
  proxy.on('error', () => {
    res.writeHead(502, { 'content-type': 'text/plain' })
    res.end('bad gateway')
  })
  req.pipe(proxy)
})

// websocket 等 upgrade 请求：原样透传（不改写）
server.on('upgrade', (req, socket) => {
  const proxy = net.connect(UPSTREAM.port, UPSTREAM.host, () => {
    proxy.write(`${req.method} ${req.url} HTTP/1.1\r\n`)
    for (const [k, v] of Object.entries(req.headers)) {
      if (Array.isArray(v)) for (const item of v) proxy.write(`${k}: ${item}\r\n`)
      else proxy.write(`${k}: ${v}\r\n`)
    }
    proxy.write('\r\n')
    socket.pipe(proxy).pipe(socket)
  })
  proxy.on('error', () => socket.destroy())
  socket.on('error', () => proxy.destroy())
})

server.listen(3080, '0.0.0.0', () => {
  console.log(`dsh proxy listening on 0.0.0.0:3080 (remote-settings: ${ALLOW_REMOTE ? 'on' : 'off'}, trusted: ${TRUSTED.length})`)
})
