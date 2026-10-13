import type { ComponentType } from 'react'
import { Header, Message } from 'semantic-ui-react'

interface SourcePanel {
  default: ComponentType
  meta?: { id: string; label: string }
}

// A source plugin (private branch) adds admin/src/sources/<id>/panel.tsx; on
// the public branch this glob is empty and the page is hidden.
const panels = import.meta.glob<SourcePanel>('../sources/*/panel.tsx', { eager: true })

export const sourcePanels = Object.entries(panels).map(([path, mod]) => ({
  id: mod.meta?.id ?? path.split('/').slice(-2)[0],
  label: mod.meta?.label ?? path.split('/').slice(-2)[0],
  Panel: mod.default,
}))

export function Sources() {
  if (sourcePanels.length === 0) return <Message info content="Aucune source supplémentaire sur cette version." />
  return (
    <>
      <Header as="h1">Sources</Header>
      {sourcePanels.map(({ id, label, Panel }) => (
        <section key={id}>
          <Header as="h2">{label}</Header>
          <Panel />
        </section>
      ))}
    </>
  )
}
