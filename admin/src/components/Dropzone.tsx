import { useRef, useState, type DragEvent } from 'react'
import { Icon } from 'semantic-ui-react'

export interface DropzoneProps {
  onFiles: (files: File[]) => void
  accept?: string
  multiple?: boolean
  title: string
  hint: string
}

/** A drop area that also opens the file picker on click. */
export function Dropzone({ onFiles, accept, multiple = true, title, hint }: DropzoneProps) {
  const input = useRef<HTMLInputElement>(null)
  const [over, setOver] = useState(false)
  const stop = (e: DragEvent) => {
    e.preventDefault()
    e.stopPropagation()
  }
  return (
    <div
      role="button"
      tabIndex={0}
      onClick={() => input.current?.click()}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') input.current?.click()
      }}
      onDragEnter={(e) => {
        stop(e)
        setOver(true)
      }}
      onDragOver={(e) => {
        stop(e)
        setOver(true)
      }}
      onDragLeave={(e) => {
        stop(e)
        setOver(false)
      }}
      onDrop={(e) => {
        stop(e)
        setOver(false)
        const files = Array.from(e.dataTransfer.files)
        if (files.length) onFiles(multiple ? files : files.slice(0, 1))
      }}
      style={{
        border: `2px dashed ${over ? '#21ba45' : '#2185d0'}`,
        background: over ? '#f0fbf2' : '#f0f7fd',
        borderRadius: 8,
        minHeight: 200,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 8,
        padding: 24,
        textAlign: 'center',
        cursor: 'pointer',
      }}
    >
      <Icon name="cloud upload" size="huge" color="blue" />
      <strong style={{ fontSize: 18 }}>{title}</strong>
      <span style={{ color: 'rgba(0,0,0,.6)' }}>{hint}</span>
      <input
        ref={input}
        type="file"
        accept={accept}
        multiple={multiple}
        style={{ display: 'none' }}
        onChange={(e) => {
          const files = Array.from(e.target.files ?? [])
          if (files.length) onFiles(files)
          e.target.value = ''
        }}
      />
    </div>
  )
}
