import handler from '../../server_api/sync/host-heartbeat.js';
import { withCors } from '../_cors.js';

export default withCors(handler);
