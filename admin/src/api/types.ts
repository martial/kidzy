// Shapes of the JSON the Go server returns (see docs/api.md).

export type ItemStatus = 'importing' | 'ready' | 'failed'

export interface Collection {
  id: string
  title: string
  kind: string
  color: string
  sortOrder: number
  visible: boolean
  created: number
  updated: number
}

export interface Item {
  id: string
  collectionId: string
  title: string
  sortOrder: number
  visible: boolean
  status: ItemStatus
  duration: number
  thumbCustom: boolean
  source: string
  sourceRef?: string
  error?: string
  created: number
  updated: number
  thumbUrl: string
  videoUrl: string
  bytes: number
  width: number
  height: number
}

export interface AdminCollection extends Collection {
  posterUrl: string
  items: Item[]
}

export interface Library {
  collections: AdminCollection[]
  orphans: Item[]
  libraryVersion: number
}

export type JobStatus = 'queued' | 'running' | 'done' | 'failed' | 'cancelled' | 'interrupted'

export interface Job {
  id: string
  kind: string
  params: unknown
  status: JobStatus
  log: string
  progress: number
  stage: string
  itemId: string
  created: number
  started: number
  finished: number
  cancel: boolean
}

export interface Bedtime {
  start: string
  end: string
}

export interface Limits {
  dailySeconds: number
  bedtime?: Bedtime
}

export interface SettingsCollection {
  id: string
  title: string
  color: string
  visible: boolean
  itemCount: number
}

export interface Settings {
  limits: Limits
  serverName: string
  finishedImageSet: boolean
  pinSet: boolean
  watchedToday: number
  collections: SettingsCollection[]
}

export interface Session {
  ok: boolean
  csrf?: string
  pinSet: boolean
  name: string
  version: string
}

export interface Device {
  id: string
  name: string
  created: number
  lastSeen: number
  revoked: boolean
}

export interface SourceInfo {
  id: string
  label: string
  status: Record<string, unknown>
}

export interface Status {
  version: string
  name: string
  addr: string
  started: string
  uptimeSeconds: number
  mediaDir: string
  inboxDir: string
  dataDir: string
  ffmpeg: string
  ffprobe: string
  workerOnline: boolean
  counts: { ready: number; importing: number; failed: number; devices: number }
  disk: { freeBytes?: number; totalBytes?: number }
  sources: SourceInfo[]
  libraryVersion: number
}
