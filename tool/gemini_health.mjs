const endpoint = process.env.POLLIE_ENDPOINT || 'https://pollie.inkpebble.workers.dev';
async function post(path, payload) {
  const response = await fetch(`${endpoint}/${path}`, {
    method: 'POST', headers: {
      'content-type': 'application/json', 'X-Install-Id': 'gemini-health-check',
    }, body: payload ? JSON.stringify(payload) : undefined,
    signal: AbortSignal.timeout(45_000),
  });
  if (!response.ok) throw new Error(`${path} returned HTTP ${response.status}: ${(await response.text()).slice(0, 1000)}`);
  return response;
}
const ping = await (await post('ping')).json();
if (ping.ok !== true) throw new Error('Gemini ping did not produce text');
const response = await post('chat', { language: 'en', messages: [
  { role: 'user', text: 'Hello Pollie! Say hello in one short sentence.' },
] });
const text = (await response.text()).split('\n').filter(line => line.trim()).map(line => {
  const part = JSON.parse(line);
  if (part.error) throw new Error(`Chat stream failed: ${part.error}`);
  return typeof part.text === 'string' ? part.text : '';
}).join('');
if (!text.trim()) throw new Error('Chat did not produce answer text');
console.log('Gemini ping and streamed greeting passed');
