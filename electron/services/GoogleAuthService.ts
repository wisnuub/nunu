import { createServer } from 'http'
import { shell } from 'electron'
import { createHash, randomBytes } from 'crypto'
import { AddressInfo } from 'net'
import { app } from 'electron'
import { join } from 'path'
import { existsSync, readFileSync } from 'fs'

export interface GoogleAuthResult {
  email: string
  name: string
  picture?: string
}

/** Read Google client ID from ~/.nunu/config.json or GOOGLE_CLIENT_ID env var. */
function resolveClientId(): string | null {
  if (process.env.GOOGLE_CLIENT_ID) return process.env.GOOGLE_CLIENT_ID

  try {
    const configPath = join(app.getPath('home'), '.nunu', 'config.json')
    if (existsSync(configPath)) {
      const config = JSON.parse(readFileSync(configPath, 'utf-8'))
      if (typeof config.googleClientId === 'string') return config.googleClientId
    }
  } catch {
    // ignore
  }

  return null
}

function base64url(buf: Buffer): string {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}

function sha256(plain: string): Buffer {
  return createHash('sha256').update(plain).digest()
}

/**
 * Opens Google OAuth in the system browser using the loopback redirect method
 * (recommended for desktop apps — works with "Desktop app" OAuth client type).
 *
 * The user must create an OAuth 2.0 client in Google Cloud Console:
 *   Type: Desktop app
 *   No redirect URIs needed (http://127.0.0.1 is allowed by default for Desktop clients)
 *
 * Then set the client ID in ~/.nunu/config.json:
 *   { "googleClientId": "YOUR_CLIENT_ID.apps.googleusercontent.com" }
 */
export async function startGoogleSignIn(): Promise<GoogleAuthResult> {
  const clientId = resolveClientId()
  if (!clientId) {
    throw new Error('NO_CLIENT_ID')
  }

  // PKCE: code verifier + challenge
  const verifier = base64url(randomBytes(32))
  const challenge = base64url(sha256(verifier))

  return new Promise((resolve, reject) => {
    // Start loopback server on a random available port
    // Capture port here — server.address() returns null after server.close()
    let serverPort = 0

    const server = createServer(async (req, res) => {
      const url = new URL(req.url ?? '/', 'http://127.0.0.1')

      if (url.pathname !== '/callback') {
        res.writeHead(404)
        res.end()
        return
      }

      const code = url.searchParams.get('code')
      const error = url.searchParams.get('error')

      res.writeHead(200, { 'Content-Type': 'text/html' })
      res.end(`<!DOCTYPE html><html><body style="font-family:sans-serif;text-align:center;padding:60px;background:#0D0F14;color:#fff">
        <h2>${error ? 'Sign-in failed' : 'Signed in — you can close this tab'}</h2>
      </body></html>`)

      // Close AFTER reading port, not before
      const port = serverPort
      server.close()

      if (error || !code) {
        reject(new Error(error ?? 'No auth code received'))
        return
      }

      try {
        const tokenRes = await exchangeCodeForToken(clientId, code, verifier, `http://127.0.0.1:${port}/callback`)
        const profile = await fetchUserProfile(tokenRes.access_token)
        resolve(profile)
      } catch (err) {
        reject(err)
      }
    })

    server.listen(0, '127.0.0.1', () => {
      serverPort = (server.address() as AddressInfo).port
      const authUrl = buildAuthURL(clientId, serverPort, challenge)
      shell.openExternal(authUrl)
    })

    server.on('error', reject)

    // Timeout after 5 minutes
    setTimeout(() => {
      server.close()
      reject(new Error('Sign-in timed out'))
    }, 300_000)
  })
}

function buildAuthURL(clientId: string, port: number, challenge: string): string {
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: `http://127.0.0.1:${port}/callback`,
    response_type: 'code',
    scope: 'openid email profile',
    code_challenge: challenge,
    code_challenge_method: 'S256',
    prompt: 'select_account',
  })
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`
}

async function exchangeCodeForToken(
  clientId: string,
  code: string,
  verifier: string,
  redirectUri: string
): Promise<{ access_token: string }> {
  const body = new URLSearchParams({
    code,
    client_id: clientId,
    redirect_uri: redirectUri,
    grant_type: 'authorization_code',
    code_verifier: verifier,
  })

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  })

  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Token exchange failed: ${text}`)
  }

  return res.json() as Promise<{ access_token: string }>
}

async function fetchUserProfile(accessToken: string): Promise<GoogleAuthResult> {
  const res = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: { Authorization: `Bearer ${accessToken}` },
  })

  if (!res.ok) throw new Error('Failed to fetch user profile')

  const data = await res.json() as { email: string; name: string; picture?: string }
  return { email: data.email, name: data.name, picture: data.picture }
}
