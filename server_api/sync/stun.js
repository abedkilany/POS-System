import dgram from 'dgram';

const MAGIC_COOKIE = 0x2112a442;

function bindingResponse(packet, remote) {
  if (!Buffer.isBuffer(packet) || packet.length < 20) return null;
  if (packet.readUInt16BE(0) !== 0x0001 || packet.readUInt32BE(4) !== MAGIC_COOKIE) {
    return null;
  }

  const transactionId = packet.subarray(8, 20);
  const attribute = Buffer.alloc(12);
  attribute.writeUInt16BE(0x0020, 0);
  attribute.writeUInt16BE(8, 2);
  attribute.writeUInt8(0, 4);
  attribute.writeUInt8(0x01, 5);
  attribute.writeUInt16BE(remote.port ^ (MAGIC_COOKIE >>> 16), 6);

  const address = remote.address.split('.').map((part) => Number(part));
  if (address.length !== 4 || address.some((part) => !Number.isInteger(part) || part < 0 || part > 255)) {
    return null;
  }
  const ip = (((address[0] << 24) >>> 0) |
    (address[1] << 16) |
    (address[2] << 8) |
    address[3]) >>> 0;
  attribute.writeUInt32BE((ip ^ MAGIC_COOKIE) >>> 0, 8);

  const response = Buffer.alloc(20 + attribute.length);
  response.writeUInt16BE(0x0101, 0);
  response.writeUInt16BE(attribute.length, 2);
  response.writeUInt32BE(MAGIC_COOKIE, 4);
  transactionId.copy(response, 8);
  attribute.copy(response, 20);
  return response;
}

export function attachStunServer({ port = Number(process.env.STUN_PORT || 3478) } = {}) {
  const socket = dgram.createSocket('udp4');
  socket.on('message', (packet, remote) => {
    const response = bindingResponse(packet, remote);
    if (response) socket.send(response, remote.port, remote.address);
  });
  socket.on('error', (error) => {
    console.error(`Ventio STUN server error: ${error.message}`);
  });
  socket.bind(port, '0.0.0.0', () => {
    const actualPort = socket.address().port;
    console.log(`Ventio STUN server listening on UDP ${actualPort}`);
  });
  return socket;
}
