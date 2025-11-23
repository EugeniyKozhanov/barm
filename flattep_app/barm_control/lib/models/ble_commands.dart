import 'dart:typed_data';

enum BleCommand {
  setSingleJoint(0x01),
  setAllJoints(0x02),
  savePosition(0x03),
  loadPosition(0x04),
  playSequence(0x05),
  stopSequence(0x06),
  getStatus(0x07),
  homePosition(0x08),
  setTorque(0x09);
  
  final int value;
  const BleCommand(this.value);
}

class BleCommandBuilder {
  // CMD 0x01: Set single joint
  static Uint8List setSingleJoint(int jointId, int position, int speed, int time) {
    assert(jointId >= 0 && jointId <= 5, 'jointId must be 0-5 (maps to servo 1-6)');
    assert(position >= 0 && position <= 4095);
    
    final buffer = ByteData(8);
    buffer.setUint8(0, BleCommand.setSingleJoint.value);
    buffer.setUint8(1, jointId);
    buffer.setUint16(2, position, Endian.little);
    buffer.setUint16(4, speed, Endian.little);
    buffer.setUint16(6, time, Endian.little);
    return buffer.buffer.asUint8List();
  }
  
  // CMD 0x02: Set all joints
  static Uint8List setAllJoints(List<int> positions, int speed, int time) {
    assert(positions.length == 6);
    
    final buffer = ByteData(17);
    buffer.setUint8(0, BleCommand.setAllJoints.value);
    for (int i = 0; i < 6; i++) {
      buffer.setUint16(1 + i * 2, positions[i], Endian.little);
    }
    buffer.setUint16(13, speed, Endian.little);
    buffer.setUint16(15, time, Endian.little);
    return buffer.buffer.asUint8List();
  }
  
  // CMD 0x03: Save position
  static Uint8List savePosition(int slot, List<int> positions) {
    assert(slot >= 0 && slot < 16);
    assert(positions.length == 6);
    
    final buffer = ByteData(14);
    buffer.setUint8(0, BleCommand.savePosition.value);
    buffer.setUint8(1, slot);
    for (int i = 0; i < 6; i++) {
      buffer.setUint16(2 + i * 2, positions[i], Endian.little);
    }
    return buffer.buffer.asUint8List();
  }
  
  // CMD 0x04: Load position
  static Uint8List loadPosition(int slot, int speed, int time) {
    assert(slot >= 0 && slot < 16);
    
    final buffer = ByteData(6);
    buffer.setUint8(0, BleCommand.loadPosition.value);
    buffer.setUint8(1, slot);
    buffer.setUint16(2, speed, Endian.little);
    buffer.setUint16(4, time, Endian.little);
    return buffer.buffer.asUint8List();
  }
  
  // CMD 0x05: Play sequence
  static Uint8List playSequence(int startSlot, int endSlot, int delayMs, bool loop) {
    assert(startSlot >= 0 && startSlot < 16);
    assert(endSlot >= 0 && endSlot < 16);
    assert(startSlot <= endSlot);
    
    final buffer = ByteData(7);
    buffer.setUint8(0, BleCommand.playSequence.value);
    buffer.setUint8(1, startSlot);
    buffer.setUint8(2, endSlot);
    buffer.setUint16(3, delayMs, Endian.little);
    buffer.setUint8(5, loop ? 1 : 0);
    return buffer.buffer.asUint8List();
  }
  
  // CMD 0x06: Stop sequence
  static Uint8List stopSequence() {
    final buffer = Uint8List(1);
    buffer[0] = BleCommand.stopSequence.value;
    return buffer;
  }
  
  // CMD 0x07: Get status
  static Uint8List getStatus() {
    final buffer = Uint8List(1);
    buffer[0] = BleCommand.getStatus.value;
    return buffer;
  }
  
  // CMD 0x08: Home position
  static Uint8List homePosition(int speed, int time) {
    final buffer = ByteData(5);
    buffer.setUint8(0, BleCommand.homePosition.value);
    buffer.setUint16(1, speed, Endian.little);
    buffer.setUint16(3, time, Endian.little);
    return buffer.buffer.asUint8List();
  }
  
  // CMD 0x09: Set torque enable/disable
  static Uint8List setTorque(bool enable) {
    final buffer = Uint8List(2);
    buffer[0] = BleCommand.setTorque.value;
    buffer[1] = enable ? 1 : 0;
    return buffer;
  }
}
