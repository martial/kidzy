import { Progress } from 'semantic-ui-react'
import type { Job } from '../api/types'

const stageLabel: Record<string, string> = { probe: 'Analyse', convert: 'Conversion', thumb: 'Vignette', download: 'Téléchargement' }

export function jobLabel(job: Job): string {
  switch (job.status) {
    case 'queued':
      return 'En attente'
    case 'running':
      return `${stageLabel[job.stage] ?? job.stage ?? 'En cours'} ${Math.round(job.progress)} %`
    case 'done':
      return 'Terminé'
    case 'failed':
      return 'Échec'
    case 'cancelled':
      return 'Annulé'
    case 'interrupted':
      return 'Interrompu'
  }
}

export function jobColor(job: Job): 'blue' | 'orange' | 'green' | 'red' | 'grey' {
  if (job.status === 'done') return 'green'
  if (job.status === 'failed') return 'red'
  if (job.status === 'running') return job.stage === 'convert' ? 'orange' : 'blue'
  return 'grey'
}

export function JobProgress({ job }: { job: Job }) {
  const pct = job.status === 'done' ? 100 : job.status === 'running' ? job.progress : 0
  return <Progress percent={Math.round(pct)} size="small" color={jobColor(job)} active={job.status === 'running'} style={{ margin: 0 }} />
}

/** The last job that concerns an item, running ones first. */
export function jobForItem(jobs: Job[], itemId: string): Job | undefined {
  const mine = jobs.filter((j) => j.itemId === itemId)
  return mine.find((j) => j.status === 'running' || j.status === 'queued') ?? mine[0]
}
