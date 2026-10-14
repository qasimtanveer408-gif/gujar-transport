import {randomBytes} from 'node:crypto';
import {writeFileSync} from 'node:fs';
writeFileSync('.session-encryption-key',randomBytes(32).toString('hex')+'\n',{mode:0o600,flag:'wx'});
console.info('Key saved to .session-encryption-key. Copy it privately into SESSION_ENCRYPTION_KEY, preserve an encrypted recovery copy, then delete the temporary file. No key was printed.');
