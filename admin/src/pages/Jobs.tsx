import { useState } from 'react'
import { Button, Header, Label, Message, Modal, Segment, Table } from 'semantic-ui-react'
import { post } from '../api/client'
import { formatDate } from '../api/format'
import { useLive } from '../api/live'
import type { Job } from '../api/types'
import { JobProgress, jobColor, jobLabel } from '../components/JobProgress'

const kindLabel: Record<string, string> = { ingest: 'Conversion' }

function labelOfKind(kind: string): string {
  return kindLabel[kind] ?? kind.replace(/-/g, ' ')
}

export function Jobs() {
  const live = useLive()
  const [open, setOpen] = useState<Job | null>(null)
  const [error, setError] = useState('')
  const shown = open ? (live.jobs.find((j) => j.id === open.id) ?? open) : null

  async function cancel(job: Job) {
    try {
      await post(`/api/admin/jobs/${job.id}/cancel`)
    } catch (e) {
      setError((e as Error).message)
    }
  }

  return (
    <>
      <Header as="h1">Tâches</Header>
      {!live.workerOnline ? <Message warning content="Le convertisseur ne répond pas : redémarrez le serveur." /> : null}
      {error ? <Message error content={error} onDismiss={() => setError('')} /> : null}
      <Segment>
        {live.jobs.length === 0 ? (
          <p style={{ color: 'rgba(0,0,0,.6)' }}>Aucune tâche.</p>
        ) : (
          <Table basic="very" compact>
            <Table.Header>
              <Table.Row>
                <Table.HeaderCell>Tâche</Table.HeaderCell>
                <Table.HeaderCell>État</Table.HeaderCell>
                <Table.HeaderCell>Avancement</Table.HeaderCell>
                <Table.HeaderCell>Créée</Table.HeaderCell>
                <Table.HeaderCell />
              </Table.Row>
            </Table.Header>
            <Table.Body>
              {live.jobs.map((j) => (
                <Table.Row key={j.id}>
                  <Table.Cell>
                    <a href="#log" onClick={(e) => { e.preventDefault(); setOpen(j) }}>
                      {labelOfKind(j.kind)}
                    </a>
                    <br />
                    <small style={{ color: 'rgba(0,0,0,.6)' }}>{lastLine(j.log)}</small>
                  </Table.Cell>
                  <Table.Cell collapsing>
                    <Label color={jobColor(j)} size="small">
                      {jobLabel(j)}
                    </Label>
                  </Table.Cell>
                  <Table.Cell style={{ minWidth: 160 }}>
                    <JobProgress job={j} />
                  </Table.Cell>
                  <Table.Cell collapsing>{formatDate(j.created)}</Table.Cell>
                  <Table.Cell collapsing>
                    {j.status === 'queued' || j.status === 'running' ? (
                      <Button size="mini" onClick={() => cancel(j)}>
                        Annuler
                      </Button>
                    ) : null}
                  </Table.Cell>
                </Table.Row>
              ))}
            </Table.Body>
          </Table>
        )}
      </Segment>
      <Modal open={!!shown} onClose={() => setOpen(null)} size="small">
        <Modal.Header>Journal · {shown ? jobLabel(shown) : ''}</Modal.Header>
        <Modal.Content scrolling>
          <pre style={{ whiteSpace: 'pre-wrap', fontSize: 12, margin: 0 }}>{shown?.log || '(vide)'}</pre>
        </Modal.Content>
        <Modal.Actions>
          <Button onClick={() => setOpen(null)}>Fermer</Button>
        </Modal.Actions>
      </Modal>
    </>
  )
}

function lastLine(log: string): string {
  const lines = log.trim().split('\n')
  const last = lines[lines.length - 1] ?? ''
  return last.replace(/^\d\d:\d\d:\d\d\s+/, '')
}
