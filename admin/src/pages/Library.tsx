import { useCallback, useEffect, useState } from 'react'
import { Button, Checkbox, Confirm, Dropdown, Header, Icon, Input, Label, Message, Modal, Segment, Table } from 'semantic-ui-react'
import { del, get, post, put, upload } from '../api/client'
import { formatBytes, formatDuration } from '../api/format'
import { useLive } from '../api/live'
import type { AdminCollection, Item, Library as LibraryData } from '../api/types'
import { JobProgress, jobForItem, jobLabel } from '../components/JobProgress'

export function Library({ navigate }: { navigate: (p: string) => void }) {
  const live = useLive()
  const [lib, setLib] = useState<LibraryData | null>(null)
  const [error, setError] = useState('')
  const [thumbFor, setThumbFor] = useState<Item | null>(null)
  const [confirmDelete, setConfirmDelete] = useState<Item | null>(null)

  const load = useCallback(async () => {
    try {
      setLib(await get<LibraryData>('/api/admin/library'))
      setError('')
    } catch (e) {
      setError((e as Error).message)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load, live.libraryVersion])

  if (error) return <Message error content={error} />
  if (!lib) return <Segment loading style={{ minHeight: 200 }} />

  const options = [
    ...lib.collections.map((c) => ({ key: c.id, value: c.id, text: c.title })),
    { key: '', value: '', text: 'Sans collection' },
  ]

  async function patchItem(item: Item, patch: Partial<Pick<Item, 'title' | 'collectionId' | 'visible'>>) {
    try {
      await put(`/api/admin/items/${item.id}`, patch)
    } catch (e) {
      setError((e as Error).message)
    }
  }

  async function move(items: Item[], index: number, dir: -1 | 1) {
    const ids = items.map((i) => i.id)
    const j = index + dir
    if (j < 0 || j >= ids.length) return
    ;[ids[index], ids[j]] = [ids[j], ids[index]]
    await put('/api/admin/items/order', { ids })
  }

  async function removeItem(item: Item) {
    setConfirmDelete(null)
    try {
      await del(`/api/admin/items/${item.id}`)
    } catch (e) {
      setError((e as Error).message)
    }
  }

  async function retry(item: Item) {
    try {
      await post(`/api/admin/items/${item.id}/retry`)
    } catch (e) {
      setError((e as Error).message)
    }
  }

  function rows(items: Item[]) {
    return items.map((item, index) => {
      const job = jobForItem(live.jobs, item.id)
      return (
        <Table.Row key={item.id} warning={item.status === 'importing'} negative={item.status === 'failed'}>
          <Table.Cell style={{ width: 96 }}>
            <button
              type="button"
              onClick={() => setThumbFor(item)}
              title="Changer la vignette"
              style={{ border: 0, padding: 0, background: 'transparent', cursor: 'pointer' }}
            >
              {item.thumbUrl ? (
                <img src={item.thumbUrl} alt="" style={{ width: 80, height: 45, objectFit: 'cover', borderRadius: 3, display: 'block' }} />
              ) : (
                <div style={{ width: 80, height: 45, borderRadius: 3, background: '#e0e1e2' }} />
              )}
            </button>
          </Table.Cell>
          <Table.Cell>
            <Input
              fluid
              defaultValue={item.title}
              onBlur={(e: React.FocusEvent<HTMLInputElement>) => {
                const title = e.target.value.trim()
                if (title && title !== item.title) void patchItem(item, { title })
              }}
            />
            {item.status === 'importing' && job ? (
              <div style={{ marginTop: 6 }}>
                <JobProgress job={job} />
                <small style={{ color: 'rgba(0,0,0,.6)' }}>{jobLabel(job)}</small>
              </div>
            ) : null}
            {item.status === 'failed' ? (
              <div style={{ marginTop: 6 }}>
                <Label color="red" size="small">
                  Échec
                </Label>{' '}
                <small>{item.error}</small>{' '}
                <Button size="mini" onClick={() => retry(item)}>
                  Réessayer
                </Button>
              </div>
            ) : null}
          </Table.Cell>
          <Table.Cell collapsing>
            {item.status === 'ready' ? (
              <>
                {formatDuration(item.duration)}
                <br />
                <small style={{ color: 'rgba(0,0,0,.6)' }}>
                  {item.width}×{item.height} · {formatBytes(item.bytes)}
                </small>
              </>
            ) : null}
          </Table.Cell>
          <Table.Cell collapsing>
            <Dropdown selection compact options={options} value={item.collectionId} onChange={(_e, { value }) => patchItem(item, { collectionId: String(value) })} />
          </Table.Cell>
          <Table.Cell collapsing>
            <Checkbox toggle checked={item.visible} onChange={(_e, { checked }) => patchItem(item, { visible: !!checked })} title="Visible pour les enfants" />
          </Table.Cell>
          <Table.Cell collapsing>
            <Button.Group size="mini" basic>
              <Button icon="arrow up" disabled={index === 0} onClick={() => move(items, index, -1)} title="Monter" />
              <Button icon="arrow down" disabled={index === items.length - 1} onClick={() => move(items, index, 1)} title="Descendre" />
            </Button.Group>
          </Table.Cell>
          <Table.Cell collapsing textAlign="right">
            <Button icon="trash" basic color="red" size="mini" onClick={() => setConfirmDelete(item)} title="Supprimer" />
          </Table.Cell>
        </Table.Row>
      )
    })
  }

  function section(title: React.ReactNode, items: Item[], extra?: React.ReactNode) {
    return (
      <Segment key={typeof title === 'string' ? title : undefined}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap', marginBottom: 10 }}>
          {title}
          {extra}
        </div>
        {items.length === 0 ? (
          <p style={{ color: 'rgba(0,0,0,.6)' }}>Aucune vidéo pour l'instant.</p>
        ) : (
          <div style={{ overflowX: 'auto' }}>
            <Table basic="very" compact>
              <Table.Header>
                <Table.Row>
                  <Table.HeaderCell>Vignette</Table.HeaderCell>
                  <Table.HeaderCell>Titre</Table.HeaderCell>
                  <Table.HeaderCell>Durée</Table.HeaderCell>
                  <Table.HeaderCell>Collection</Table.HeaderCell>
                  <Table.HeaderCell>Visible</Table.HeaderCell>
                  <Table.HeaderCell>Ordre</Table.HeaderCell>
                  <Table.HeaderCell />
                </Table.Row>
              </Table.Header>
              <Table.Body>{rows(items)}</Table.Body>
            </Table>
          </div>
        )}
      </Segment>
    )
  }

  const collectionHeader = (c: AdminCollection) => (
    <>
      <span style={{ width: 14, height: 14, borderRadius: '50%', background: c.color, border: '2px solid #1F2A44', display: 'inline-block' }} />
      <Header as="h3" style={{ margin: 0 }}>
        {c.title}
      </Header>
      <span style={{ color: 'rgba(0,0,0,.6)' }}>
        {kindLabel(c.kind)} · {c.items.filter((i) => i.status === 'ready').length} vidéo{c.items.length > 1 ? 's' : ''} · {c.visible ? 'visible' : 'masquée'}
      </span>
      <Button size="small" style={{ marginLeft: 'auto' }} onClick={() => navigate('/admin/collections')}>
        Gérer les collections
      </Button>
    </>
  )

  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>
        <Header as="h1" style={{ margin: 0 }}>
          Bibliothèque
        </Header>
        <Button primary onClick={() => navigate('/admin/envoyer')}>
          <Icon name="upload" />
          Ajouter des vidéos
        </Button>
      </div>
      {lib.collections.length === 0 && lib.orphans.length === 0 ? (
        <Message info>
          <Message.Header>Rien pour l'instant</Message.Header>
          Déposez des vidéos dans « Envoyer », ou dans le dossier <code>~/Kidzy/inbox/&lt;collection&gt;/</code> du Mac.
        </Message>
      ) : null}
      {lib.collections.map((c) => section(collectionHeader(c), c.items))}
      {lib.orphans.length > 0
        ? section(
            <>
              <Header as="h3" style={{ margin: 0 }}>
                Sans collection
              </Header>
              <span style={{ color: 'rgba(0,0,0,.6)' }}>invisibles pour les enfants tant qu'elles n'ont pas de collection</span>
            </>,
            lib.orphans,
          )
        : null}

      <Confirm
        open={!!confirmDelete}
        header="Supprimer la vidéo ?"
        content={confirmDelete ? `« ${confirmDelete.title} » et son fichier seront supprimés.` : ''}
        cancelButton="Garder"
        confirmButton="Supprimer"
        onCancel={() => setConfirmDelete(null)}
        onConfirm={() => confirmDelete && removeItem(confirmDelete)}
      />
      {thumbFor ? <ThumbModal item={thumbFor} onClose={() => setThumbFor(null)} onError={setError} /> : null}
    </>
  )
}

export function kindLabel(kind: string): string {
  return kind === 'songs' ? 'Chansons' : kind === 'films' ? 'Films' : 'Série'
}

function ThumbModal({ item, onClose, onError }: { item: Item; onClose: () => void; onError: (m: string) => void }) {
  const [at, setAt] = useState(Math.round(Math.max(5, item.duration * 0.1)))
  const [busy, setBusy] = useState(false)
  async function fromFrame() {
    setBusy(true)
    try {
      await post(`/api/admin/items/${item.id}/thumb`, { at })
      onClose()
    } catch (e) {
      onError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  async function fromFile(file: File) {
    setBusy(true)
    try {
      await upload(`/api/admin/items/${item.id}/thumb`, file, {}, () => {}).promise
      onClose()
    } catch (e) {
      onError((e as Error).message)
    } finally {
      setBusy(false)
    }
  }
  return (
    <Modal open size="tiny" onClose={onClose}>
      <Modal.Header>Vignette de « {item.title} »</Modal.Header>
      <Modal.Content>
        {item.thumbUrl ? <img src={item.thumbUrl} alt="" style={{ width: '100%', borderRadius: 4, marginBottom: 12 }} /> : null}
        {item.status === 'ready' ? (
          <p>
            Prendre l'image à la seconde{' '}
            <Input type="number" min={0} max={Math.floor(item.duration)} value={at} onChange={(_e, { value }) => setAt(Number(value))} style={{ width: 100 }} />{' '}
            <Button size="small" loading={busy} onClick={fromFrame}>
              Prendre
            </Button>
          </p>
        ) : null}
        <p>
          Ou choisir une image :{' '}
          <input
            type="file"
            accept="image/*"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) void fromFile(f)
            }}
          />
        </p>
      </Modal.Content>
      <Modal.Actions>
        <Button onClick={onClose}>Fermer</Button>
      </Modal.Actions>
    </Modal>
  )
}
