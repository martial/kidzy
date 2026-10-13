import { Icon, Menu } from 'semantic-ui-react'
import { useLive } from '../api/live'

export interface NavProps {
  path: string
  navigate: (path: string) => void
  hasSources: boolean
  serverName: string
  onLogout: () => void
}

const items: [string, string][] = [
  ['/admin/', 'Bibliothèque'],
  ['/admin/envoyer', 'Envoyer'],
  ['/admin/collections', 'Collections'],
  ['/admin/reglages', 'Réglages'],
  ['/admin/taches', 'Tâches'],
  ['/admin/etat', 'État'],
]

export function Nav({ path, navigate, hasSources, serverName, onLogout }: NavProps) {
  const live = useLive()
  const active = live.jobs.filter((j) => j.status === 'running' || j.status === 'queued').length
  const entries = hasSources ? [...items, ['/admin/sources', 'Sources'] as [string, string]] : items
  return (
    <Menu secondary pointing stackable style={{ background: '#fff', borderBottom: '1px solid rgba(34,36,38,.15)', margin: 0, padding: '0 16px' }}>
      <Menu.Item header onClick={() => navigate('/admin/')} style={{ fontSize: 18 }}>
        <Icon name="sun" color="yellow" />
        Kidzy
      </Menu.Item>
      {entries.map(([p, label]) => (
        <Menu.Item key={p} name={label} active={path === p} onClick={() => navigate(p)}>
          {label}
          {p === '/admin/taches' && active > 0 ? <span className="ui mini circular blue label">{active}</span> : null}
        </Menu.Item>
      ))}
      <Menu.Menu position="right">
        <Menu.Item>
          <Icon name="circle" color={live.workerOnline ? 'green' : 'red'} />
          {serverName}
          {live.connected ? '' : ' · hors ligne ?'}
        </Menu.Item>
        <Menu.Item onClick={onLogout}>
          <Icon name="sign-out" />
          Quitter
        </Menu.Item>
      </Menu.Menu>
    </Menu>
  )
}
