// One EventSource for the whole admin: jobs, library version and worker
// status, with polling as a fallback when the stream is unavailable.
import { useEffect, useState } from 'react'
import { get } from './client'
import type { Job } from './types'

export interface Live {
  jobs: Job[]
  workerOnline: boolean
  libraryVersion: number
  connected: boolean
}

type Listener = (live: Live) => void

let state: Live = { jobs: [], workerOnline: true, libraryVersion: -1, connected: false }
const listeners = new Set<Listener>()
let source: EventSource | null = null
let pollTimer: number | undefined
let started = false

function emit(patch: Partial<Live>) {
  state = { ...state, ...patch }
  for (const l of listeners) l(state)
}

async function poll() {
  try {
    const r = await get<{ jobs: Job[]; workerOnline: boolean }>('/api/admin/jobs')
    emit({ jobs: r.jobs, workerOnline: r.workerOnline })
  } catch {
    // the session may be gone; the client already raised the event
  }
}

function connect() {
  if (source) source.close()
  source = new EventSource('/api/admin/events')
  source.addEventListener('jobs', (e) => emit({ jobs: (JSON.parse((e as MessageEvent).data) as { jobs: Job[] }).jobs, connected: true }))
  source.addEventListener('library', (e) => emit({ libraryVersion: (JSON.parse((e as MessageEvent).data) as { version: number }).version }))
  source.addEventListener('status', (e) => emit({ workerOnline: (JSON.parse((e as MessageEvent).data) as { workerOnline: boolean }).workerOnline }))
  source.addEventListener('expired', () => {
    source?.close()
    window.location.reload()
  })
  source.onopen = () => {
    emit({ connected: true })
    if (pollTimer) {
      window.clearInterval(pollTimer)
      pollTimer = undefined
    }
  }
  source.onerror = () => {
    emit({ connected: false })
    if (!pollTimer) pollTimer = window.setInterval(poll, 3000)
  }
}

/** Starts the stream once (after login). */
export function startLive() {
  if (started) return
  started = true
  connect()
}

export function stopLive() {
  started = false
  source?.close()
  source = null
  if (pollTimer) window.clearInterval(pollTimer)
  pollTimer = undefined
}

export function useLive(): Live {
  const [live, setLive] = useState(state)
  useEffect(() => {
    listeners.add(setLive)
    setLive(state)
    return () => {
      listeners.delete(setLive)
    }
  }, [])
  return live
}
