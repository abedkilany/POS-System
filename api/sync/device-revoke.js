import handler from '../../server_api/sync/device-revoke.js';
import { withCors } from '../_cors.js';

export default withCors(handler);
