import React, { useState } from 'react'

const SERVER = (import.meta as any).env?.VITE_SERVER_URL || 'http://127.0.0.1:8080'

export default function App() {
  const [prompt, setPrompt] = useState('')
  const [status, setStatus] = useState<string>('')
  const [log, setLog] = useState<string>('')
  const [finalMessage, setFinalMessage] = useState<string>('')
  const [runId, setRunId] = useState<string>('')

  async function submit() {
    setStatus('Submitting...')
    setLog('')
    setFinalMessage('')
    setRunId('')
    try {
      const url = `${SERVER}/commands/submit_query`
      setLog(`POST ${url}`)
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ prompt })
      })
      if (!res.ok) {
        const txt = await res.text()
        throw new Error(`Server error: ${res.status} ${txt}`)
      }
      const data = await res.json()
      setRunId(data.run_id || '')
      setFinalMessage(data.final_message || '(no final message)')
      setStatus('Done')
    } catch (e: any) {
      setStatus(`Error: ${e?.message || String(e)}`)
      setLog(prev => `${prev}\n${e?.stack || ''}`)
    }
  }

  return (
    <div style={{ fontFamily: 'sans-serif', padding: 16 }}>
      <h1>Cedar Desktop (MVP)</h1>
      <p>Ask a question. The backend runs the agent loop and returns the final response.</p>
      <div style={{ display: 'flex', gap: 8 }}>
        <input
          style={{ flex: 1, padding: 8 }}
          placeholder="Ask Cedar..."
          value={prompt}
          onChange={e => setPrompt(e.target.value)}
        />
        <button onClick={submit}>Ask</button>
      </div>
      <p>Status: {status}</p>
      {runId && (
        <p>Run ID: <code>{runId}</code></p>
      )}
      {finalMessage && (
        <div>
          <h3>Final</h3>
          <pre style={{ whiteSpace: 'pre-wrap' }}>{finalMessage}</pre>
        </div>
      )}
      <hr />
      <details>
        <summary>Logs</summary>
        <pre style={{ whiteSpace: 'pre-wrap', background: '#eee', padding: 8 }}>
          {log}
        </pre>
      </details>
      <small>Server: {SERVER}. Configure with VITE_SERVER_URL.</small>
    </div>
  )
}
