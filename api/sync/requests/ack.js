import handler from '../../../server_api/sync/requests/ack.js';
import { withCors } from '../../_cors.js';

export default withCors(handler);
