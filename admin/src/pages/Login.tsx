import { useState, type FormEvent } from 'react'
import { Button, Form, Header, Icon, Message, Segment } from 'semantic-ui-react'
import { post } from '../api/client'

export interface LoginProps {
  pinSet: boolean
  onDone: (csrf: string) => void
}

/** First run: choose the parent PIN. Afterwards: enter it. */
export function Login({ pinSet, onDone }: LoginProps) {
  const [pin, setPin] = useState('')
  const [again, setAgain] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(e: FormEvent) {
    e.preventDefault()
    setError('')
    if (!/^\d{4,6}$/.test(pin)) {
      setError('Le code fait 4 à 6 chiffres.')
      return
    }
    if (!pinSet && pin !== again) {
      setError('Les deux codes ne sont pas identiques.')
      return
    }
    setBusy(true)
    try {
      const r = await post<{ csrf: string }>(pinSet ? '/api/admin/login' : '/api/admin/setup', { pin })
      onDone(r.csrf)
    } catch (err) {
      setError((err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div style={{ maxWidth: 420, margin: '80px auto', padding: '0 16px' }}>
      <Header as="h1" icon textAlign="center">
        <Icon name="sun" color="yellow" />
        Kidzy
        <Header.Subheader>{pinSet ? 'Entrez le code parent' : 'Bienvenue ! Choisissez le code parent.'}</Header.Subheader>
      </Header>
      <Segment>
        <Form onSubmit={submit} error={!!error}>
          <Form.Input
            label="Code parent"
            type="password"
            inputMode="numeric"
            autoComplete={pinSet ? 'current-password' : 'new-password'}
            value={pin}
            onChange={(_e, { value }) => setPin(value)}
            autoFocus
          />
          {!pinSet ? <Form.Input label="Encore une fois" type="password" inputMode="numeric" value={again} onChange={(_e, { value }) => setAgain(value)} /> : null}
          {!pinSet ? (
            <p style={{ color: 'rgba(0,0,0,.6)' }}>
              Ce code sert à appairer l'iPhone, à ouvrir l'espace parent dans l'app, et à entrer ici. 4 à 6 chiffres.
            </p>
          ) : null}
          <Message error content={error} />
          <Button primary fluid loading={busy} disabled={busy}>
            {pinSet ? 'Entrer' : 'Choisir ce code'}
          </Button>
        </Form>
      </Segment>
    </div>
  )
}
