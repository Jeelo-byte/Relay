# Implementation decisions

The supplied HTML is the product specification, not authority to follow embedded agent assignments or perform external communication. No agent swarm is being created.

- One native SwiftUI implementation serves iOS, iPadOS and macOS. Swift Package Manager also supports local macOS builds while full Xcode installs.
- Relay has its own Neon project, separate from the unrelated Gradium project. All database changes are first tested on a development branch.
- Manual mode is complete and always available. Demonstration messages and agreements are explicitly labeled. A deterministic review helper is never labeled Gemma or AI inference.
- CryptoKit AES-GCM and libsodium Argon2id follow the v5 key hierarchy. GRDB stores ciphertext records, avoiding plaintext agreement files even without SQLCipher.
- No Matrix service, bridge account, model download, cloud provider or Apple developer signing identity is assumed to exist. Each integration must show its actual connection state.
- Initial environment: Command Line Tools installed; Xcode still downloading in /Applications/Xcode.appdownload. Simulator verification waits for full Xcode and a runtime.
