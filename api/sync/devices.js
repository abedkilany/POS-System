import handler from '../../server_api/sync/devices.js';
import { withCors } from '../_cors.js';

export default withCors(handler);
