use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Error, FromSample, Sample, SampleFormat, SizedSample};
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
        // The transcription model wants mono at 16 kHz: if the mic delivers
        // stereo, mix it down to mono, otherwise transcription comes out
        // double-speed.
        let channels = config.channels() as usize;
        let stream_config: cpal::StreamConfig = config.into();
        let buffer: Arc<Mutex<Vec<f32>>> = Arc::new(Mutex::new(Vec::new()));

        // Every format the platform may hand us. Missing one here made
        // recording fail outright on some Windows and Linux machines whose
        // default device reports u8, i32 or f64 instead of f32/i16/u16.
        let err_fn = |e| eprintln!("audio: {e}");
        let stream = match config.sample_format() {
            SampleFormat::I8 => {
                open_stream::<i8>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::I16 => {
                open_stream::<i16>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::I32 => {
                open_stream::<i32>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::I64 => {
                open_stream::<i64>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::U8 => {
                open_stream::<u8>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::U16 => {
                open_stream::<u16>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::U32 => {
                open_stream::<u32>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::U64 => {
                open_stream::<u64>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::F32 => {
                open_stream::<f32>(&device, &stream_config, channels, &buffer, err_fn)
            }
            SampleFormat::F64 => {
                open_stream::<f64>(&device, &stream_config, channels, &buffer, err_fn)
            }
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

fn open_stream<S>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    channels: usize,
    buffer: &Arc<Mutex<Vec<f32>>>,
    err_fn: impl FnMut(Error) + Send + 'static,
) -> Result<cpal::Stream, Error>
where
    S: SizedSample,
    f32: FromSample<S>,
{
    let buf_clone = buffer.clone();
    device.build_input_stream(
        *config,
        move |data: &[S], _| {
            if let Ok(mut b) = buf_clone.lock() {
                if channels <= 1 {
                    b.extend(data.iter().map(|&s| f32::from_sample(s)));
                } else {
                    b.extend(data.chunks_exact(channels).map(|frame| {
                        frame.iter().map(|&s| f32::from_sample(s)).sum::<f32>() / channels as f32
                    }));
                }
            }
        },
        err_fn,
        None,
    )
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resample_passthrough_at_16k() {
        let samples = vec![0.1, 0.2, 0.3];
        assert_eq!(resample_to_16k(&samples, 16_000), samples);
    }

    #[test]
    fn resample_empty_input() {
        assert!(resample_to_16k(&[], 48_000).is_empty());
    }

    #[test]
    fn resample_halves_length_from_32k() {
        let samples: Vec<f32> = (0..1000).map(|i| i as f32 / 1000.0).collect();
        let out = resample_to_16k(&samples, 32_000);
        assert_eq!(out.len(), 500);
        // The first sample must survive nearly unchanged.
        assert!((out[0] - samples[0]).abs() < 1e-3);
    }

    #[test]
    fn resample_upsamples_from_8k() {
        let samples: Vec<f32> = (0..250).map(|i| i as f32 / 250.0).collect();
        let out = resample_to_16k(&samples, 8_000);
        assert_eq!(out.len(), 500);
    }

    #[test]
    fn resample_values_stay_in_range() {
        let samples: Vec<f32> = (0..4800).map(|i| (i as f32 / 4800.0) * 2.0 - 1.0).collect();
        let out = resample_to_16k(&samples, 48_000);
        assert!(out
            .iter()
            .all(|v| v.is_finite() && (-1.5..=1.5).contains(v)));
    }
}
