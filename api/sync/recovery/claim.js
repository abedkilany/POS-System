import handler from '../../../server_api/sync/recovery/claim.js';
import { withCors } from '../../_cors.js';

export default withCors(handler);
