import handler from '../../../server_api/sync/host-transfer/list.js';
import { withCors } from '../../_cors.js';

export default withCors(handler);
