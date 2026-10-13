import { useEffect, useRef, useState } from 'react'
import { Button, Dropdown, Header, Input, Message, Progress, Segment } from 'semantic-ui-react'
import { get, upload, type UploadHandle } from '../api/client'
import { formatBytes } from '../api/format'
import { useLive } from '../api/live'
import type { Library } from '../api/types'
import { Dropzone } from '../components/Dropzone'
import { jobLabel } from '../components/JobProgress'

interface Transfer {
  key: number
  file: File
  sent: number
  status: 'waiting' | 'sending' | 'queued' | 'done' | 'failed' | 'cancelled'
  error?: string
  itemId?: string
  jobId?: string
  handle?: UploadHandle
}

const PARALLEL = 2
const NEW = '__new__'

export function Upload({ navigate }: { navigate: (p: string) => void }) {
  const live = useLive()
  const [collections, setCollections] = useState<{ id: string; title: string }[]>([])
  const [collectionId, setCollectionId] = useState('')
  const [newTitle, setNewTitle] = useState('')
  const [transfers, setTransfers] = useState<Transfer[]>([])
  const counter = useRef(0)

  useEffect(() => {
    get<Library>('/api/admin/library')
      .then((l) => {
        setCollections(l.collections.map((c) => ({ id: c.id, title: c.title })))
        if (!collectionId && l.collections[0]) setCollectionId(l.collections[0].id)
      })
      .catch(() => {})
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [live.libraryVersion])

  function update(key: number, patch: Partial<Transfer>) {
    setTransfers((ts) => ts.map((t) => (t.key === key ? { ...t, ...patch } : t)))
  }

  function addFiles(files: File[]) {
    const added = files.map((file) => ({ key: ++counter.current, file, sent: 0, status: 'waiting' as const }))
    setTransfers((ts) => [...ts, ...added])
  }

  // start waiting transfers while fewer than PARALLEL are sending
  useEffect(() => {
    const sending = transfers.filter((t) => t.status === 'sending').length
    const next = transfers.find((t) => t.status === 'waiting')
    if (!next || sending >= PARALLEL) return
    const fields: Record<string, string> = {}
    if (collectionId === NEW) fields.collectionTitle = newTitle.trim()
    else if (collectionId) fields.collectionId = collectionId
    const handle = upload('/api/admin/upload', next.file, fields, (sent) => update(next.key, { sent }))
    update(next.key, { status: 'sending', handle })
    handle.promise
      .then((r) => {
        const res = r as { itemId: string; jobId: string }
        update(next.key, { status: 'queued', itemId: res.itemId, jobId: res.jobId, sent: next.file.size })
      })
      .catch((e: Error) => update(next.key, { status: e.message === 'annulé' ? 'cancelled' : 'failed', error: e.message }))
  }, [transfers, collectionId, newTitle])

  const options = [
    ...collections.map((c) => ({ key: c.id, value: c.id, text: c.title })),
    { key: NEW, value: NEW, text: 'Nouvelle collection…' },
    { key: '', value: '', text: 'Sans collection' },
  ]

  return (
    <>
      <Header as="h1">Envoyer des vidéos</Header>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginBottom: 16 }}>
        <strong>Ajouter à la collection</strong>
        <Dropdown selection options={options} value={collectionId} onChange={(_e, { value }) => setCollectionId(String(value))} style={{ minWidth: 220 }} />
        {collectionId === NEW ? <Input placeholder="Nom de la nouvelle collection" value={newTitle} onChange={(_e, { value }) => setNewTitle(value)} /> : null}
      </div>
      <Dropzone
        onFiles={addFiles}
        accept="video/*,.mkv,.avi,.webm,.mov,.mp4,.m4v,.ts,.flv,.wmv,.mpg,.mpeg"
        title="Déposez vos vidéos ici, ou cliquez pour choisir"
        hint="MP4, MOV, MKV, AVI, WebM… Chaque fichier est converti pour l'iPhone, puis apparaît dans la bibliothèque."
      />
      {transfers.length > 0 ? (
        <Segment>
          {transfers.map((t) => {
            const job = t.jobId ? live.jobs.find((j) => j.id === t.jobId) : undefined
            const pct = t.status === 'sending' || t.status === 'waiting' ? Math.round((t.sent / Math.max(1, t.file.size)) * 100) : job ? (job.status === 'done' ? 100 : Math.round(job.progress)) : t.status === 'queued' ? 0 : 100
            const color = t.status === 'failed' || job?.status === 'failed' ? 'red' : job?.status === 'done' ? 'green' : job?.status === 'running' ? 'orange' : 'blue'
            const label =
              t.status === 'waiting'
                ? 'En attente'
                : t.status === 'sending'
                  ? `Envoi ${pct} % · ${formatBytes(t.file.size)}`
                  : t.status === 'failed'
                    ? `Échec : ${t.error}`
                    : t.status === 'cancelled'
                      ? 'Annulé'
                      : job
                        ? job.status === 'done'
                          ? 'Prête, dans la bibliothèque'
                          : jobLabel(job)
                        : 'Reçue, en attente de conversion'
            return (
              <div key={t.key} style={{ display: 'flex', alignItems: 'center', gap: 14, flexWrap: 'wrap', padding: '10px 0', borderBottom: '1px solid rgba(34,36,38,.1)' }}>
                <strong style={{ flex: '0 0 260px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{t.file.name}</strong>
                <Progress percent={pct} color={color} size="small" active={t.status === 'sending' || job?.status === 'running'} style={{ flex: '1 1 220px', margin: 0 }} />
                <span style={{ flex: '0 0 260px', color: color === 'red' ? '#db2828' : 'rgba(0,0,0,.6)' }}>{label}</span>
                {t.status === 'sending' || t.status === 'waiting' ? (
                  <Button size="mini" onClick={() => (t.handle ? t.handle.abort() : update(t.key, { status: 'cancelled' }))}>
                    Annuler
                  </Button>
                ) : job?.status === 'done' ? (
                  <Button size="mini" onClick={() => navigate('/admin/')}>
                    Voir
                  </Button>
                ) : null}
              </div>
            )
          })}
        </Segment>
      ) : null}
      <Message>
        Autre chemin, sans navigateur : déposez les fichiers dans le dossier <code>~/Kidzy/inbox/&lt;collection&gt;/</code> du Mac (le sous-dossier fait la collection). Le serveur les prend en charge tout seul et vide le dossier.
      </Message>
    </>
  )
}
