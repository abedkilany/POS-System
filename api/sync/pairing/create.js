import handler from '../../../server_api/sync/pairing/create.js';
import { withCors } from '../../_cors.js';

export default withCors(handler);
