// Fetch wrapper for the admin API: JSON in and out, the CSRF token on every
// write, a global event when the session is gone, and XHR uploads with progress.

let csrf = ''

export function setCsrf(token: string | undefined) {
  csrf = token ?? ''
}

export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

export const UNAUTHORIZED_EVENT = 'kidzy:unauthorized'

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = {}
  let payload: BodyInit | undefined
  if (method !== 'GET') headers['X-CSRF-Token'] = csrf
  if (body instanceof FormData) payload = body
  else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }
  const res = await fetch(path, { method, headers, body: payload, credentials: 'same-origin' })
  const text = await res.text()
  let data: unknown = null
  try {
    data = text ? JSON.parse(text) : null
  } catch {
    data = null
  }
  if (res.status === 401) window.dispatchEvent(new Event(UNAUTHORIZED_EVENT))
  if (!res.ok) {
    const msg = (data as { error?: string } | null)?.error ?? `${res.status} ${res.statusText}`
    throw new ApiError(msg, res.status)
  }
  return data as T
}

export const get = <T>(path: string) => request<T>('GET', path)
export const post = <T>(path: string, body?: unknown) => request<T>('POST', path, body)
export const put = <T>(path: string, body?: unknown) => request<T>('PUT', path, body)
export const del = <T>(path: string) => request<T>('DELETE', path)

export interface UploadHandle {
  promise: Promise<unknown>
  abort: () => void
}

/** Uploads one file as multipart "file" with progress, the way banana radio's admin does. */
export function upload(path: string, file: File, fields: Record<string, string>, onProgress: (sent: number, total: number) => void): UploadHandle {
  const xhr = new XMLHttpRequest()
  const promise = new Promise<unknown>((resolve, reject) => {
    const form = new FormData()
    for (const [k, v] of Object.entries(fields)) form.append(k, v)
    form.append('file', file, file.name)
    xhr.open('POST', path)
    xhr.setRequestHeader('X-CSRF-Token', csrf)
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) onProgress(e.loaded, e.total)
    }
    xhr.onload = () => {
      let data: unknown = null
      try {
        data = xhr.responseText ? JSON.parse(xhr.responseText) : null
      } catch {
        data = null
      }
      if (xhr.status === 401) window.dispatchEvent(new Event(UNAUTHORIZED_EVENT))
      if (xhr.status >= 200 && xhr.status < 300) resolve(data)
      else reject(new ApiError((data as { error?: string } | null)?.error ?? `${xhr.status}`, xhr.status))
    }
    xhr.onerror = () => reject(new ApiError('envoi interrompu', 0))
    xhr.onabort = () => reject(new ApiError('annulé', 0))
    xhr.send(form)
  })
  return { promise, abort: () => xhr.abort() }
}
