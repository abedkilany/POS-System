import handler from '../../server_api/sync/push.js';
import { withCors } from '../_cors.js';

export default withCors(handler);
