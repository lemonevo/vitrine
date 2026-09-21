# SSH agent

Serve the SSH keys already stored in the vault to `ssh` and anything that talks to it, over a Unix
socket. Read-only with respect to the vault: the agent adds nothing and removes nothing.

Prizm already stores SSH private keys (`SSHKeyContent.privateKey`) but offers no way to use them.
This is the only capability in this change that no other Prizm feature competes with, and it is the
one that only a desktop client can have.

## ADDED Requirements

### Requirement: the agent SHALL listen on a Unix socket it owns

The socket SHALL be created under a directory whose permissions are `0700`, owned by the user, and
the socket itself SHALL NOT be world-accessible. Prizm SHALL NOT reuse or overwrite a socket path it
did not create, and SHALL remove the socket file when it stops.

#### Scenario: the socket is created when the agent is enabled

- **GIVEN** the vault is unlocked and the user has enabled the agent
- **WHEN** the agent starts
- **THEN** the socket exists at the documented path, inside a `0700` directory

#### Scenario: the environment cannot host the socket

- **GIVEN** the process cannot bind the socket — including because it is running under the App
  Sandbox, where a socket usable by `ssh` cannot be created at all
- **WHEN** the agent is enabled
- **THEN** Prizm reports that the agent is unavailable **and why**
- **AND** it does not report success, and does not retry silently in a loop

> A listener that fails under the sandbox is a real possibility, not a hypothetical: the release
> build is sandboxed by default and local builds are not. The failure must be visible, because an
> agent that silently serves nobody looks, to the user, like an agent that is protecting them.

### Requirement: Prizm SHALL answer identity listing

Prizm SHALL answer `SSH_AGENTC_REQUEST_IDENTITIES` with the SSH keys in the vault that it can
actually use, and SHALL omit the ones it cannot.

#### Scenario: a key Prizm cannot use is not offered

- **GIVEN** a vault holding an ed25519 key and an ECDSA key
- **WHEN** a client requests identities
- **THEN** only the ed25519 key is listed
- **AND** Prizm names the omitted one, and why, in Settings rather than leaving it unexplained

#### Scenario: the comment shown is the item

- **GIVEN** a vault item named `Deploy key — staging` whose stored key carries its own comment
- **WHEN** a client requests identities
- **THEN** the comment in the answer is `Deploy key — staging`
- **AND NOT** the comment stored inside the key file

> The comment is what `ssh-add -l` prints. The user's own name for the item is the one that tells
> them which key it is; the key file's comment is whatever the machine that generated it said.

### Requirement: the agent SHALL refuse to sign without a grant from the master-password gate

Every `SSH_AGENTC_SIGN_REQUEST` SHALL be routed through the gate before any signature is produced.
Signing SHALL NOT happen as a side effect of the vault being unlocked.

The gate SHALL grant per key per unlock session: the first request for a key asks for the master
password, later requests for that key in the same session do not. Grants SHALL be cleared by the
same teardown that clears the reprompt grants — `lockVault()` and `signOut()`.

#### Scenario: the first request for a key asks

- **GIVEN** the agent is enabled and no request has been made for key `K` this session
- **WHEN** a client asks Prizm to sign with `K`
- **THEN** Prizm presents the master-password prompt naming `K` and, where it can be determined,
  the process that asked
- **AND** nothing is signed until the password is confirmed

#### Scenario: the password is wrong

- **WHEN** the wrong master password is entered
- **THEN** no grant is issued and the client receives `SSH_AGENT_FAILURE`

#### Scenario: the request is declined

- **WHEN** the prompt is cancelled
- **THEN** no grant is issued and the client receives `SSH_AGENT_FAILURE`

#### Scenario: a later request for the same key

- **GIVEN** key `K` was granted earlier in this session
- **WHEN** a client asks Prizm to sign with `K` again
- **THEN** the signature is produced without prompting again

#### Scenario: locking clears it

- **GIVEN** key `K` was granted
- **WHEN** the vault locks
- **THEN** the next request for `K` asks again

> The task says "every sign request goes through the master-password gate", and it does: no
> signature is produced without consulting the gate. What the gate *returns* on a later request is a
> grant it issued earlier in the session. Prompting on every single signature would make any `git`
> operation that signs more than once unusable, and an agent the user turns off protects nothing —
> which is the outcome this requirement exists to prevent.
>
> Naming the requesting process is what makes the prompt answerable. Without it the user is asked to
> approve a signature with no idea what asked for it, which trains them to press yes.

### Requirement: Prizm SHALL support the key formats it can, and say which it cannot

Prizm SHALL use unencrypted OpenSSH-format (`openssh-key-v1`) ed25519 and RSA private keys. Any
other key SHALL be left out of the identity list with a stated reason, never half-loaded.

#### Scenario: an encrypted key

- **GIVEN** a vault item whose private key is encrypted with a passphrase
- **WHEN** identities are listed
- **THEN** the key is omitted and Settings says it is passphrase-protected

> Prizm stores no passphrase for an SSH key, so there is nothing to decrypt it with. Offering the
> key and then failing at sign time would be worse: the failure would surface in `ssh`, far from
> the reason.

#### Scenario: an unsupported algorithm

- **GIVEN** a vault item holding an ECDSA key
- **WHEN** identities are listed
- **THEN** the key is omitted and Settings names the algorithm as unsupported

### Requirement: Prizm SHALL implement only the protocol it needs

Prizm SHALL answer `SSH_AGENTC_REQUEST_IDENTITIES` and `SSH_AGENTC_SIGN_REQUEST`, and SHALL answer
`SSH_AGENT_FAILURE` to every other message — including the key-management messages, which would let
a client insert or delete keys.

#### Scenario: an unrecognised message

- **WHEN** a client sends a message Prizm does not implement
- **THEN** the answer is `SSH_AGENT_FAILURE`
- **AND** the connection stays open

> Answering failure to `ADD_IDENTITY` rather than ignoring it matters: a client that gets no reply
> may wait until it times out, and a client that gets `SSH_AGENT_FAILURE` moves on immediately.
> Neither is an error condition Prizm needs to log as a fault.

### Requirement: Prizm SHALL NOT retain key material between requests

The private key SHALL be parsed when a signature is requested and discarded afterwards. Identities
SHALL be built from public material only.

#### Scenario: no key is held while idle

- **WHEN** no signing request is in flight
- **THEN** Prizm holds no parsed private key

## Out of scope

Registering or asserting WebAuthn credentials, forwarding to another agent, and `ADD`/`REMOVE`
identity management. The agent serves what is in the vault and nothing else.
