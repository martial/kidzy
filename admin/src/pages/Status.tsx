import { useCallback, useEffect, useState } from 'react'
import { Button, Header, Icon, Message, Segment, Statistic, Table } from 'semantic-ui-react'
import { get } from '../api/client'
import { formatBytes, formatDuration } from '../api/format'
import type { Status as StatusData } from '../api/types'

export function Status() {
  const [data, setData] = useState<StatusData | null>(null)
  const [error, setError] = useState('')
  const load = useCallback(async () => {
    try {
      setData(await get<StatusData>('/api/admin/status'))
    } catch (e) {
      setError((e as Error).message)
    }
  }, [])
  useEffect(() => {
    void load()
  }, [load])

  if (error) return <Message error content={error} />
  if (!data) return <Segment loading style={{ minHeight: 200 }} />
  const free = data.disk.freeBytes ?? 0
  const total = data.disk.totalBytes ?? 0
  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 12 }}>
        <Header as="h1" style={{ margin: 0 }}>
          État du serveur
        </Header>
        <Button onClick={load} icon labelPosition="left">
          <Icon name="refresh" />
          Actualiser
        </Button>
      </div>
      <Segment>
        <Statistic.Group size="small" widths="four">
          <Statistic>
            <Statistic.Value>{data.counts.ready}</Statistic.Value>
            <Statistic.Label>vidéos prêtes</Statistic.Label>
          </Statistic>
          <Statistic>
            <Statistic.Value>{data.counts.importing}</Statistic.Value>
            <Statistic.Label>en conversion</Statistic.Label>
          </Statistic>
          <Statistic color={data.counts.failed ? 'red' : undefined}>
            <Statistic.Value>{data.counts.failed}</Statistic.Value>
            <Statistic.Label>en échec</Statistic.Label>
          </Statistic>
          <Statistic>
            <Statistic.Value>{formatBytes(free)}</Statistic.Value>
            <Statistic.Label>libres sur {formatBytes(total)}</Statistic.Label>
          </Statistic>
        </Statistic.Group>
      </Segment>
      <Segment>
        <Table basic="very" compact definition>
          <Table.Body>
            <Table.Row>
              <Table.Cell collapsing>Serveur</Table.Cell>
              <Table.Cell>
                <Icon name="circle" color={data.workerOnline ? 'green' : 'red'} /> {data.name} · version {data.version} · en marche depuis {formatDuration(data.uptimeSeconds)} · écoute sur {data.addr}
              </Table.Cell>
            </Table.Row>
            <Table.Row>
              <Table.Cell>Dossier des vidéos</Table.Cell>
              <Table.Cell>
                <code>{data.mediaDir}</code> (déposez dans <code>{data.inboxDir}</code>)
              </Table.Cell>
            </Table.Row>
            <Table.Row>
              <Table.Cell>Données</Table.Cell>
              <Table.Cell>
                <code>{data.dataDir}</code>
              </Table.Cell>
            </Table.Row>
            <Table.Row>
              <Table.Cell>ffmpeg</Table.Cell>
              <Table.Cell>{data.ffmpeg || <span style={{ color: '#db2828' }}>introuvable : brew install ffmpeg</span>}</Table.Cell>
            </Table.Row>
            <Table.Row>
              <Table.Cell>ffprobe</Table.Cell>
              <Table.Cell>{data.ffprobe || <span style={{ color: '#db2828' }}>introuvable</span>}</Table.Cell>
            </Table.Row>
            <Table.Row>
              <Table.Cell>iPhones appairés</Table.Cell>
              <Table.Cell>{data.counts.devices}</Table.Cell>
            </Table.Row>
            {data.sources.map((s) => (
              <Table.Row key={s.id}>
                <Table.Cell>{s.label}</Table.Cell>
                <Table.Cell>
                  {Object.entries(s.status).map(([k, v]) => (
                    <span key={k} style={{ marginRight: 12 }}>
                      {k} : {String(v)}
                    </span>
                  ))}
                </Table.Cell>
              </Table.Row>
            ))}
          </Table.Body>
        </Table>
      </Segment>
    </>
  )
}
