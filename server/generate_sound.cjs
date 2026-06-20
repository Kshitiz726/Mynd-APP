const fs = require('fs');
const path = require('path');
const sampleRate = 44100;
const duration = 0.35; // seconds
const numSamples = Math.floor(sampleRate * duration);
const buffer = Buffer.alloc(44 + numSamples * 2);

// WAV Header
buffer.write('RIFF', 0);
buffer.writeUInt32LE(36 + numSamples * 2, 4);
buffer.write('WAVE', 8);
buffer.write('fmt ', 12);
buffer.writeUInt32LE(16, 16);
buffer.writeUInt16LE(1, 20); // PCM
buffer.writeUInt16LE(1, 22); // Mono
buffer.writeUInt32LE(sampleRate, 24);
buffer.writeUInt32LE(sampleRate * 2, 28); // Byte rate
buffer.writeUInt16LE(2, 32); // Block align
buffer.writeUInt16LE(16, 34); // Bits per sample
buffer.write('data', 36);
buffer.writeUInt32LE(numSamples * 2, 40);

// Generate two-tone beep (like Discord join)
for (let i = 0; i < numSamples; i++) {
  const t = i / sampleRate;
  let freq = t < 0.15 ? 440 : 587.33; // A4 to D5
  
  // ADSR envelope for smooth sound
  let env = 1;
  if (t < 0.02) env = t / 0.02;
  else if (t > 0.13 && t < 0.15) env = (0.15 - t) / 0.02;
  else if (t > 0.15 && t < 0.17) env = (t - 0.15) / 0.02;
  else if (t > 0.3) env = (0.35 - t) / 0.05;

  // Add a slight harmonic to make it sound better than a raw sine wave
  const sine1 = Math.sin(2 * Math.PI * freq * t);
  const sine2 = Math.sin(2 * Math.PI * freq * 2 * t) * 0.2;
  const sample = (sine1 + sine2) * env * 0.2 * 32767;
  
  buffer.writeInt16LE(Math.max(-32768, Math.min(32767, Math.round(sample))), 44 + i * 2);
}

const dir = path.join(__dirname, '../assets/audio');
if (!fs.existsSync(dir)) {
  fs.mkdirSync(dir, { recursive: true });
}
fs.writeFileSync(path.join(dir, 'join.wav'), buffer);
console.log('Audio generated successfully!');
