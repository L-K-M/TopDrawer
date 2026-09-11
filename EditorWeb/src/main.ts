import { EditorSession } from './session';
// Imported after the editor module on purpose: the editor pulls in Crepe's
// stylesheets, and these overrides must come last to win ties. Keep this line
// below the import above.
import './theme.css';

const container = document.getElementById('editor');
if (!container) throw new Error('missing #editor container');

const session = new EditorSession(container);
session.start();
