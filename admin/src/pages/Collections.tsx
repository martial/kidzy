import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, Checkbox, Confirm, Dropdown, Form, Header, Input, Message, Segment, Table } from 'semantic-ui-react'
import { del, get, post, put, upload } from '../api/client'
import { useLive } from '../api/live'
import type { AdminCollection, Library } from '../api/types'
import { kindLabel } from './Library'

const kinds = [
  { key: 'show', value: 'show', text: 'Série (épisodes dans l\u2019ordre)' },
  { key: 'songs', value: 'songs', text: 'Chansons' },
  { key: 'films', value: 'films', text: 'Films' },
]

export function Collections() {
  const live = useLive()
  const [cols, setCols] = useState<AdminCollection[] | null>(null)
  const [error, setError] = useState('')
  const [title, setTitle] = useState('')
  const [kind, setKind] = useState('show')
  const [confirm, setConfirm] = useState<AdminCollection | null>(null)

  const load = useCallback(async () => {
    try {
      setCols((await get<Library>('/api/admin/library')).collections)
    } catch (e) {
      setError((e as Error).message)
    }
  }, [])
  useEffect(() => {
    void load()
  }, [load, live.libraryVersion])

  async function create(e: FormEvent) {
    e.preventDefault()
    if (!title.trim()) return
    try {
      await post('/api/admin/collections', { title: title.trim(), kind })
      setTitle('')
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function patch(c: AdminCollection, body: Partial<Pick<AdminCollection, 'title' | 'kind' | 'visible' | 'color'>>) {
    try {
      await put(`/api/admin/collections/${c.id}`, body)
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function move(index: number, dir: -1 | 1) {
    if (!cols) return
    const ids = cols.map((c) => c.id)
    const j = index + dir
    if (j < 0 || j >= ids.length) return
    ;[ids[index], ids[j]] = [ids[j], ids[index]]
    await put('/api/admin/collections/order', { ids })
  }

  async function remove(c: AdminCollection) {
    setConfirm(null)
    try {
      await del(`/api/admin/collections/${c.id}`)
    } catch (err) {
      setError((err as Error).message)
    }
  }

  async function poster(c: AdminCollection, file: File) {
    try {
      await upload(`/api/admin/collections/${c.id}/poster`, file, {}, () => {}).promise
    } catch (err) {
      setError((err as Error).message)
    }
  }

  if (error) return <Message error content={error} onDismiss={() => setError('')} />
  if (!cols) return <Segment loading style={{ minHeight: 200 }} />

  return (
    <>
      <Header as="h1">Collections</Header>
      <Segment>
        <Form onSubmit={create}>
          <Form.Group inline>
            <Form.Field>
              <Input placeholder="Nom de la collection" value={title} onChange={(_e, { value }) => setTitle(value)} />
            </Form.Field>
            <Form.Field>
              <Dropdown selection options={kinds} value={kind} onChange={(_e, { value }) => setKind(String(value))} />
            </Form.Field>
            <Button primary disabled={!title.trim()}>
              Créer
            </Button>
          </Form.Group>
        </Form>
      </Segment>
      <Segment>
        <div style={{ overflowX: 'auto' }}>
          <Table basic="very" compact>
            <Table.Header>
              <Table.Row>
                <Table.HeaderCell>Affiche</Table.HeaderCell>
                <Table.HeaderCell>Nom</Table.HeaderCell>
                <Table.HeaderCell>Type</Table.HeaderCell>
                <Table.HeaderCell>Vidéos</Table.HeaderCell>
                <Table.HeaderCell>Visible</Table.HeaderCell>
                <Table.HeaderCell>Ordre</Table.HeaderCell>
                <Table.HeaderCell />
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {cols.map((c, index) => (
                <Table.Row key={c.id}>
                  <Table.Cell collapsing>
                    <label title="Changer l'affiche" style={{ cursor: 'pointer', display: 'inline-block', position: 'relative' }}>
                      {c.posterUrl ? (
                        <img src={c.posterUrl} alt="" style={{ width: 64, height: 64, objectFit: 'cover', borderRadius: 8, border: `4px solid ${c.color}` }} />
                      ) : (
                        <div style={{ width: 64, height: 64, borderRadius: 8, background: c.color }} />
                      )}
                      <input
                        type="file"
                        accept="image/*"
                        style={{ display: 'none' }}
                        onChange={(e) => {
                          const f = e.target.files?.[0]
                          if (f) void poster(c, f)
                          e.target.value = ''
                        }}
                      />
                    </label>
                  </Table.Cell>
                  <Table.Cell>
                    <Input
                      fluid
                      defaultValue={c.title}
                      onBlur={(e: React.FocusEvent<HTMLInputElement>) => {
                        const t = e.target.value.trim()
                        if (t && t !== c.title) void patch(c, { title: t })
                      }}
                    />
                  </Table.Cell>
                  <Table.Cell collapsing>
                    <Dropdown selection compact options={kinds.map((k) => ({ ...k, text: kindLabel(k.value) }))} value={c.kind} onChange={(_e, { value }) => patch(c, { kind: String(value) })} />
                  </Table.Cell>
                  <Table.Cell collapsing>{c.items.filter((i) => i.status === 'ready').length}</Table.Cell>
                  <Table.Cell collapsing>
                    <Checkbox toggle checked={c.visible} onChange={(_e, { checked }) => patch(c, { visible: !!checked })} />
                  </Table.Cell>
                  <Table.Cell collapsing>
                    <Button.Group size="mini" basic>
                      <Button icon="arrow up" disabled={index === 0} onClick={() => move(index, -1)} />
                      <Button icon="arrow down" disabled={index === cols.length - 1} onClick={() => move(index, 1)} />
                    </Button.Group>
                  </Table.Cell>
                  <Table.Cell collapsing textAlign="right">
                    <Button icon="trash" basic color="red" size="mini" onClick={() => setConfirm(c)} />
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table>
        </div>
        <p style={{ color: 'rgba(0,0,0,.6)' }}>L'affiche est l'image de la collection sur l'iPhone ; sans affiche, c'est la vignette de la première vidéo. Cliquez l'affiche pour la changer.</p>
      </Segment>
      <Confirm
        open={!!confirm}
        header="Supprimer la collection ?"
        content={confirm ? `« ${confirm.title} » disparaît ; ses vidéos restent, sans collection.` : ''}
        cancelButton="Garder"
        confirmButton="Supprimer"
        onCancel={() => setConfirm(null)}
        onConfirm={() => confirm && remove(confirm)}
      />
    </>
  )
}
