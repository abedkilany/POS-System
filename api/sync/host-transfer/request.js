import handler from '../../../server_api/sync/host-transfer/request.js';
import { withCors } from '../../_cors.js';

export default withCors(handler);
