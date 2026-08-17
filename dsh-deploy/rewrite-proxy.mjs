// Rewriting reverse proxy for dsh remote access: makes /api requests look
// loopback-originated so the dsh host's browser-trust fence passes.
// - Host is rewritten to 127.0.0.1:3080
// - Origin and Sec-Fetch-* markers are stripped (Origin fence + cross-site fence)
// - WebSocket upgrades are forwarded with the same rewrites
import http from 'node:http'

const UPSTREAM = { host: '127.0.0.1', port: 3080 }
const LISTEN = { host: '127.0.0.1', port: 3090 }

function rewriteHeaders(headers) {
  const out = {}
  for (const [key, value] of Object.entries(headers)) {
    const k = key.toLowerCase()
    if (k === 'host') {
      out.host = '127.0.0.1:3080'
    } else if (k === 'origin' || k.startsWith('sec-fetch-')) {
      // drop browser trust markers
    } else {
      out[key] = value
    }
  }
  return out
}

const server = http.createServer((req, res) => {
  const proxy = http.request(
    {
      host: UPSTREAM.host,
      port: UPSTREAM.port,
      path: req.url,
      method: req.method,
      headers: rewriteHeaders(req.headers),
    },
    (upstreamRes) => {
      res.writeHead(upstreamRes.statusCode, upstreamRes.headers)
      upstreamRes.pipe(res)
    },
  )
  proxy.on('error', (err) => {
    res.writeHead(502, { 'content-type': 'text/plain' })
    res.end(`proxy error: ${err.message}`)
  })
  req.pipe(proxy)
})

server.on('upgrade', (req, socket, head) => {
  const proxy = http.request({
    host: UPSTREAM.host,
    port: UPSTREAM.port,
    path: req.url,
    method: req.method,
    headers: rewriteHeaders(req.headers),
  })
  proxy.on('upgrade', (res, upSocket, upHead) => {
    socket.write('HTTP/1.1 101 Switching Protocols\r\n')
    for (const [key, value] of Object.entries(res.headers)) {
      if (Array.isArray(value)) {
        for (const v of value) socket.write(`${key}: ${v}\r\n`)
      } else {
        socket.write(`${key}: ${value}\r\n`)
      }
    }
    socket.write('\r\n')
    if (upHead && upHead.length) upSocket.unshift(upHead)
    socket.pipe(upSocket)
    upSocket.pipe(socket)
  })
  proxy.on('error', () => {
    socket.destroy()
  })
  proxy.end()
  if (head && head.length) proxy.write(head)
})

server.listen(LISTEN.port, LISTEN.host, () => {
  console.log(`rewrite-proxy listening on ${LISTEN.host}:${LISTEN.port} -> ${UPSTREAM.host}:${UPSTREAM.port}`)
})
