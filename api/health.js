import handler from '../server_api/health.js';
import { withCors } from './_cors.js';

export default withCors(handler);
