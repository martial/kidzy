import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, Checkbox, Form, Header, Input, Message, Segment, Table } from 'semantic-ui-react'
import { del, get, post, put, upload } from '../api/client'
import { formatAgo, formatDuration } from '../api/format'
import type { Device, Settings as SettingsData } from '../api/types'

export function Settings() {
  const [data, setData] = useState<SettingsData | null>(null)
  const [devices, setDevices] = useState<Device[]>([])
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [daily, setDaily] = useState(false)
  const [minutes, setMinutes] = useState(45)
  const [bed, setBed] = useState(false)
  const [start, setStart] = useState('19:30')
  const [end, setEnd] = useState('07:00')
  const [imageVersion, setImageVersion] = useState(0)
  const [current, setCurrent] = useState('')
  const [pin, setPin] = useState('')
  const [again, setAgain] = useState('')

  const load = useCallback(async () => {
    try {
      const s = await get<SettingsData>('/api/admin/settings')
      setData(s)
      setDaily(s.limits.dailySeconds > 0)
      if (s.limits.dailySeconds > 0) setMinutes(Math.round(s.limits.dailySeconds / 60))
      setBed(!!s.limits.bedtime)
      if (s.limits.bedtime) {
        setStart(s.limits.bedtime.start)
        setEnd(s.limits.bedtime.end)
      }
      setDevices((await get<{ devices: Device[] }>('/api/admin/devices')).devices)
    } catch (e) {
      setError((e as Error).message)
    }
  }, [])
  useEffect(() => {
    void load()
  }, [load])

  async function saveLimits(e: FormEvent) {
    e.preventDefault()
    setError('')
    try {
      await put('/api/admin/settings', {
        limits: { dailySeconds: daily ? Math.max(1, minutes) * 60 : 0, bedtime: bed ? { start, end } : undefined },
      })
      setNotice('Limites enregistrées.')
      await load()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function changePin(e: FormEvent) {
    e.preventDefault()
    setError('')
    if (pin !== again) {
      setError('Les deux codes ne sont pas identiques.')
      return
    }
    try {
      await post('/api/admin/settings/pin', { pin, current })
      setNotice('Code parent changé.')
      setCurrent('')
      setPin('')
      setAgain('')
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function setImage(file: File) {
    setError('')
    try {
      await upload('/api/admin/finished-image', file, {}, () => {}).promise
      setImageVersion((v) => v + 1)
      await load()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function resetImage() {
    try {
      await del('/api/admin/finished-image')
      setImageVersion((v) => v + 1)
      await load()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function revoke(d: Device) {
    try {
      await del(`/api/admin/devices/${d.id}`)
      await load()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  if (!data) return <Segment loading style={{ minHeight: 200 }} />

  return (
    <>
      <Header as="h1">Réglages</Header>
      {error ? <Message error content={error} onDismiss={() => setError('')} /> : null}
      {notice ? <Message success content={notice} onDismiss={() => setNotice('')} /> : null}

      <Segment>
        <Header as="h3">Temps d'écran</Header>
        <Form onSubmit={saveLimits}>
          <Form.Group inline>
            <Form.Field>
              <Checkbox label="Limite par jour" checked={daily} onChange={(_e, { checked }) => setDaily(!!checked)} />
            </Form.Field>
            <Form.Field>
              <Input type="number" min={1} max={600} value={minutes} disabled={!daily} onChange={(_e, { value }) => setMinutes(Number(value))} style={{ width: 90 }} /> minutes
            </Form.Field>
          </Form.Group>
          <Form.Group inline>
            <Form.Field>
              <Checkbox label="Pas de vidéo entre" checked={bed} onChange={(_e, { checked }) => setBed(!!checked)} />
            </Form.Field>
            <Form.Field>
              <Input type="time" value={start} disabled={!bed} onChange={(_e, { value }) => setStart(value)} /> et{' '}
              <Input type="time" value={end} disabled={!bed} onChange={(_e, { value }) => setEnd(value)} />
            </Form.Field>
          </Form.Group>
          <p style={{ color: 'rgba(0,0,0,.6)' }}>
            Quand la limite est atteinte, l'app reste sur l'image ci-dessous ; seul le code parent permet d'en sortir. Aujourd'hui : {formatDuration(data.watchedToday)} regardées.
          </p>
          <Button primary>Enregistrer</Button>
        </Form>
      </Segment>

      <Segment>
        <div style={{ display: 'flex', gap: 18, flexWrap: 'wrap', alignItems: 'center' }}>
          <div style={{ width: 120, height: 260, borderRadius: 12, overflow: 'hidden', border: '1px solid rgba(34,36,38,.15)', background: '#232B4E', flex: '0 0 auto' }}>
            {data.finishedImageSet ? <img src={`/api/admin/finished-image?v=${imageVersion}`} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : null}
          </div>
          <div style={{ flex: '1 1 320px' }}>
            <Header as="h3">Image de fin de journée</Header>
            <p style={{ color: 'rgba(0,0,0,.6)' }}>L'image que l'enfant voit quand c'est terminé. Une photo verticale de la famille marche très bien. {data.finishedImageSet ? '' : 'Par défaut : la lune qui dort, dessinée dans l\u2019app.'}</p>
            <label className="ui primary button" style={{ cursor: 'pointer' }}>
              Changer l'image
              <input
                type="file"
                accept="image/jpeg,image/png,image/webp"
                style={{ display: 'none' }}
                onChange={(e) => {
                  const f = e.target.files?.[0]
                  if (f) void setImage(f)
                  e.target.value = ''
                }}
              />
            </label>{' '}
            {data.finishedImageSet ? <Button onClick={resetImage}>Remettre la lune</Button> : null}
          </div>
        </div>
      </Segment>

      <Segment>
        <Header as="h3">Code parent</Header>
        <p style={{ color: 'rgba(0,0,0,.6)' }}>Le même code sert à appairer un iPhone, à ouvrir l'espace parent dans l'app et à entrer ici. 4 à 6 chiffres.</p>
        <Form onSubmit={changePin}>
          <Form.Group inline>
            <Form.Input type="password" inputMode="numeric" placeholder="Code actuel" value={current} onChange={(_e, { value }) => setCurrent(value)} autoComplete="current-password" />
            <Form.Input type="password" inputMode="numeric" placeholder="Nouveau code" value={pin} onChange={(_e, { value }) => setPin(value)} autoComplete="new-password" />
            <Form.Input type="password" inputMode="numeric" placeholder="Encore une fois" value={again} onChange={(_e, { value }) => setAgain(value)} autoComplete="new-password" />
            <Button primary disabled={!pin || !current}>
              Changer le code
            </Button>
          </Form.Group>
        </Form>
      </Segment>

      <Segment>
        <Header as="h3">Appareils appairés</Header>
        {devices.filter((d) => !d.revoked).length === 0 ? (
          <p style={{ color: 'rgba(0,0,0,.6)' }}>Aucun iPhone pour l'instant. L'app s'appaire toute seule avec le code parent, une fois le serveur trouvé sur le réseau.</p>
        ) : (
          <Table basic="very" compact>
            <Table.Body>
              {devices
                .filter((d) => !d.revoked)
                .map((d) => (
                  <Table.Row key={d.id}>
                    <Table.Cell>
                      <strong>{d.name}</strong>
                    </Table.Cell>
                    <Table.Cell style={{ color: 'rgba(0,0,0,.6)' }}>
                      appairé le {new Date(d.created).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' })}, vu {formatAgo(d.lastSeen)}
                    </Table.Cell>
                    <Table.Cell collapsing>
                      <Button basic color="red" size="mini" onClick={() => revoke(d)}>
                        Révoquer
                      </Button>
                    </Table.Cell>
                  </Table.Row>
                ))}
            </Table.Body>
          </Table>
        )}
        <p style={{ color: 'rgba(0,0,0,.6)' }}>
          Nom du serveur sur le réseau : <strong>{data.serverName}</strong>
        </p>
      </Segment>
    </>
  )
}
