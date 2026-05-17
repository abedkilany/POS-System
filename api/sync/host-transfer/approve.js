import handler from '../../../server_api/sync/host-transfer/approve.js';
import { withCors } from '../../_cors.js';

export default withCors(handler);
