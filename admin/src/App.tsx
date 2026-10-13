import { useCallback, useEffect, useState } from 'react'
import { Container } from 'semantic-ui-react'
import { get, post, setCsrf, UNAUTHORIZED_EVENT } from './api/client'
import { startLive, stopLive } from './api/live'
import type { Session } from './api/types'
import { Nav } from './components/Nav'
import { Collections } from './pages/Collections'
import { Jobs } from './pages/Jobs'
import { Library } from './pages/Library'
import { Login } from './pages/Login'
import { Settings } from './pages/Settings'
import { Sources, sourcePanels } from './pages/Sources'
import { Status } from './pages/Status'
import { Upload } from './pages/Upload'

function currentPath(): string {
  const p = window.location.pathname.replace(/\/+$/, '')
  return p === '/admin' || p === '' ? '/admin/' : p
}

export function App() {
  const [session, setSession] = useState<Session | null>(null)
  const [path, setPath] = useState(currentPath())

  const navigate = useCallback((p: string) => {
    window.history.pushState(null, '', p)
    setPath(p)
    window.scrollTo(0, 0)
  }, [])

  useEffect(() => {
    const onPop = () => setPath(currentPath())
    window.addEventListener('popstate', onPop)
    return () => window.removeEventListener('popstate', onPop)
  }, [])

  const refresh = useCallback(async () => {
    try {
      const s = await get<Session>('/api/admin/session')
      setCsrf(s.csrf)
      setSession(s)
      if (s.ok) startLive()
    } catch {
      setSession({ ok: false, pinSet: true, name: 'Kidzy', version: '' })
    }
  }, [])

  useEffect(() => {
    void refresh()
    const onUnauthorized = () => {
      stopLive()
      setSession((s) => (s ? { ...s, ok: false, csrf: undefined } : s))
    }
    const onName = (e: Event) => setSession((s) => (s ? { ...s, name: String((e as CustomEvent).detail) } : s))
    window.addEventListener(UNAUTHORIZED_EVENT, onUnauthorized)
    window.addEventListener('kidzy:name', onName)
    return () => {
      window.removeEventListener(UNAUTHORIZED_EVENT, onUnauthorized)
      window.removeEventListener('kidzy:name', onName)
    }
  }, [refresh])

  async function logout() {
    try {
      await post('/api/admin/logout')
    } catch {
      // the cookie is gone either way
    }
    stopLive()
    setSession((s) => (s ? { ...s, ok: false, csrf: undefined } : s))
  }

  if (!session) return null
  if (!session.ok) {
    return (
      <Login
        pinSet={session.pinSet}
        onDone={(csrf) => {
          setCsrf(csrf)
          setSession({ ...session, ok: true, pinSet: true, csrf })
          startLive()
        }}
      />
    )
  }

  let page: React.ReactNode
  switch (path) {
    case '/admin/envoyer':
      page = <Upload navigate={navigate} />
      break
    case '/admin/collections':
      page = <Collections />
      break
    case '/admin/reglages':
      page = <Settings />
      break
    case '/admin/taches':
      page = <Jobs />
      break
    case '/admin/etat':
      page = <Status />
      break
    case '/admin/sources':
      page = <Sources />
      break
    default:
      page = <Library navigate={navigate} />
  }

  return (
    <div style={{ minHeight: '100vh', background: '#F7F8FA' }}>
      <Nav path={path} navigate={navigate} hasSources={sourcePanels.length > 0} serverName={session.name} onLogout={logout} />
      <Container style={{ padding: '28px 0 48px' }}>{page}</Container>
    </div>
  )
}
