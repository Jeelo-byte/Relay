# Local Gemma on Mac

Relay uses Gemma 4 E2B. Builds with the MLX dependencies load the pinned model
inside the native app. A Mac build made with an older Swift toolchain can use
the installed Ollama runtime instead; the Load button remains available.

For this compatibility runtime, install Ollama from its official source, start
it on this Mac, and download the pinned 4-bit model:

```sh
OLLAMA_HOST=127.0.0.1:11434 OLLAMA_NO_CLOUD=1 ollama serve
# In another terminal:
ollama pull gemma4:e2b-it-q4_K_M
```

The download is about 4.6 GB. In Relay, open **Settings → Processing & Workspace**
and choose **Download and Load Gemma**. Previously downloaded models load
automatically when Relay starts. Successful loading shows
**Local · Gemma 4 E2B (Ollama)**. Ollama must keep running for inference.

Relay only connects to `127.0.0.1:11434`. It does not accept a remote model host
or follow HTTP redirects. It verifies the model's manifest digest before loading
and uses an ephemeral session without saved credentials, cookies, or proxies.
Model prompts stay on this Mac. Account sync separately uploads encrypted
agreements and recaps through the configured Relay account server.

Turn on **Automatic AI** to process selected conversations after five quiet
minutes, or choose **Check Quiet Conversations**. Quotes are checked against
original messages, suggested agreements still need review, and no replies are
sent automatically. The compatibility runtime has a bounded 32K context and
rejects oversized prompts or incomplete output rather than saving a partial
summary. Original messages remain available when validation fails.

Check the runtime using `ollama ps`; it shows the loaded model and GPU usage.
The model remains available for 24 hours after a request. A local login agent
can keep `ollama serve` running, with `OLLAMA_NO_CLOUD=1` and the loopback host
above. Do not expose the Ollama port through Relay's phone gateway or Funnel.

The Mac compatibility runtime does not change the native iPhone model runtime.
Paired devices can receive encrypted recaps and agreements through account sync.
