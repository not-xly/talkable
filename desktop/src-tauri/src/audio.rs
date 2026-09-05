use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};

/// Records from the default microphone until `stop` is called.
/// The stream lives and dies on the same thread (an ALSA requirement on Linux).
pub struct Recorder {
    stream: Option<cpal::Stream>,
    buffer: Arc<Mutex<Vec<f32>>>,
    sample_rate: u32,
    keep_going: Arc<std::sync::atomic::AtomicBool>,
}

impl Recorder {
    pub fn start() -> Result<Self, String> {
        use std::sync::atomic::AtomicBool;

        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or_else(|| "No microphone available".to_string())?;
        let config = device
            .default_input_config()
            .map_err(|e| format!("Microphone config: {e}"))?;
        let sample_rate = config.sample_rate();
        // Whisper wants mono at 16 kHz: if the mic delivers stereo, mix it
        // down to mono, otherwise transcription comes out double-speed.
        let channels = config.channels() as usize;
        let stream_config: cpal::StreamConfig = config.clone().into();
        let buffer: Arc<Mutex<Vec<f32>>> = Arc::new(Mutex::new(Vec::new()));

        let buf_clone = buffer.clone();
        let err_fn = |e| eprintln!("audio: {e}");

        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => device.build_input_stream(
                stream_config.clone(),
                move |data: &[f32], _| {
                    if let Ok(mut b) = buf_clone.lock() {
                        if channels <= 1 {
                            b.extend_from_slice(data);
                        } else {
                            b.extend(
                                data.chunks_exact(channels)
                                    .map(|f| f.iter().sum::<f32>() / channels as f32),
                            );
                        }
                    }
                },
                err_fn,
                None,
            ),
            cpal::SampleFormat::I16 => device.build_input_stream(
                stream_config.clone(),
                move |data: &[i16], _| {
                    if let Ok(mut b) = buf_clone.lock() {
                        if channels <= 1 {
                            b.extend(data.iter().map(|&s| s as f32 / 32768.0));
                        } else {
                            b.extend(data.chunks_exact(channels).map(|f| {
                                f.iter().map(|&s| s as f32 / 32768.0).sum::<f32>()
                                    / channels as f32
                            }));
                        }
                    }
                },
                err_fn,
                None,
            ),
            cpal::SampleFormat::U16 => device.build_input_stream(
                stream_config.clone(),
                move |data: &[u16], _| {
                    if let Ok(mut b) = buf_clone.lock() {
                        if channels <= 1 {
                            b.extend(data.iter().map(|&s| (s as f32 - 32768.0) / 32768.0));
                        } else {
                            b.extend(data.chunks_exact(channels).map(|f| {
                                f.iter()
                                    .map(|&s| (s as f32 - 32768.0) / 32768.0)
                                    .sum::<f32>()
                                    / channels as f32
                            }));
                        }
                    }
                },
                err_fn,
                None,
            ),
            other => return Err(format!("Unsupported audio format: {other}")),
        }
        .map_err(|e| format!("Couldn't open the microphone: {e}"))?;

        stream.play().map_err(|e| format!("Couldn't record: {e}"))?;

        Ok(Self {
            stream: Some(stream),
            buffer,
            sample_rate,
            keep_going: Arc::new(AtomicBool::new(true)),
        })
    }

    pub fn keep_going(&self) -> Arc<std::sync::atomic::AtomicBool> {
        self.keep_going.clone()
    }

    /// Stops recording and returns the samples, resampled to 16 kHz.
    pub fn stop(mut self) -> Vec<f32> {
        use std::sync::atomic::Ordering;
        self.keep_going.store(false, Ordering::SeqCst);
        self.stream.take(); // dropped on the same thread
        let (samples, rate) = {
            let b = self.buffer.lock().map(|b| b.clone()).unwrap_or_default();
            (b, self.sample_rate)
        };
        resample_to_16k(&samples, rate)
    }
}

/// Linear resampling (good enough for voice).
fn resample_to_16k(samples: &[f32], from: u32) -> Vec<f32> {
    if from == 16_000 || samples.is_empty() {
        return samples.to_vec();
    }
    let ratio = f64::from(from) / 16_000.0;
    let out_len = (samples.len() as f64 / ratio).floor() as usize;
    (0..out_len)
        .map(|i| {
            let pos = i as f64 * ratio;
            let i0 = pos.floor() as usize;
            let i1 = (i0 + 1).min(samples.len() - 1);
            let frac = (pos - i0 as f64) as f32;
            samples[i0] * (1.0 - frac) + samples[i1] * frac
        })
        .collect()
}
