import React, { useState } from 'react'
import { invoke } from '@tauri-apps/api/tauri'

export default function App() {
  const [prompt, setPrompt] = useState('')
  const [status, setStatus] = useState('')
  const [log, setLog] = useState('')
  const [finalMessage, setFinalMessage] = useState('')
  const [runId, setRunId] = useState('')

  async function submit() {
    setStatus('Submitting...')
    setLog('')
    setFinalMessage('')
    setRunId('')
    try {
      const data = await invoke<{ 
        run_id?: string; final_message?: string; 
      }>('cmd_submit_query', { body: { prompt } })   // ← matches #[tauri::command]
      setRunId(data.run_id ?? '')
      setFinalMessage(data.final_message ?? '(no final message)')
      setStatus('Done')
    } catch (e: any) {
      setStatus(`Error: ${e?.message || String(e)}`)
      setLog(prev => `${prev}\n${e?.stack || ''}`)
    }
  }

  // … render stays the same
}
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
