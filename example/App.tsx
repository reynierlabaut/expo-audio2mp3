import * as DocumentPicker from 'expo-document-picker';
import { File, Paths } from 'expo-file-system';
import { StatusBar } from 'expo-status-bar';
import { useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {
  Audio2Mp3Error,
  convertToMp3,
  type ConvertResult,
  type Mp3Bitrate,
} from 'expo-audio2mp3';

const BITRATES: Mp3Bitrate[] = [64, 128, 192, 256, 320];

type Picked = { uri: string; name: string; size?: number };

type Outcome =
  | { kind: 'ok'; result: ConvertResult; elapsedMs: number }
  | { kind: 'error'; code: string; message: string };

export default function App() {
  const [picked, setPicked] = useState<Picked | null>(null);
  const [bitrate, setBitrate] = useState<Mp3Bitrate>(192);
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);

  async function pick() {
    const res = await DocumentPicker.getDocumentAsync({
      type: ['video/*', 'audio/*'],
      copyToCacheDirectory: true,
    });
    if (!res.canceled) {
      const asset = res.assets[0];
      setPicked({ uri: asset.uri, name: asset.name, size: asset.size });
      setOutcome(null);
    }
  }

  async function convert() {
    if (!picked) return;
    setBusy(true);
    setOutcome(null);
    const baseName = picked.name.replace(/\.[^.]+$/, '') || 'audio';
    const output = new File(Paths.document, `${baseName}-${bitrate}.mp3`).uri;
    const start = Date.now();
    try {
      const result = await convertToMp3({ input: picked.uri, output, bitrate, overwrite: true });
      setOutcome({ kind: 'ok', result, elapsedMs: Date.now() - start });
    } catch (error) {
      const e = error as Audio2Mp3Error;
      setOutcome({ kind: 'error', code: e.code ?? 'UNKNOWN', message: e.message });
    } finally {
      setBusy(false);
    }
  }

  return (
    <SafeAreaView style={styles.screen}>
      <StatusBar style="auto" />
      <ScrollView contentContainerStyle={styles.content}>
        <Text style={styles.title}>expo-audio2mp3</Text>

        <Button label="Elegir vídeo o audio" onPress={pick} disabled={busy} />
        {picked && (
          <Text style={styles.muted}>
            {picked.name}
            {picked.size ? ` · ${(picked.size / 1024 / 1024).toFixed(1)} MB` : ''}
          </Text>
        )}

        <Text style={styles.label}>Bitrate (kbps)</Text>
        <View style={styles.row}>
          {BITRATES.map(b => (
            <Pressable
              key={b}
              onPress={() => setBitrate(b)}
              style={[styles.chip, b === bitrate && styles.chipActive]}>
              <Text style={b === bitrate ? styles.chipTextActive : undefined}>{b}</Text>
            </Pressable>
          ))}
        </View>

        <Button label="Convertir a MP3" onPress={convert} disabled={!picked || busy} />
        {busy && <ActivityIndicator style={styles.spinner} />}

        {outcome?.kind === 'ok' && (
          <View style={styles.card}>
            <Text style={styles.ok}>Listo en {(outcome.elapsedMs / 1000).toFixed(1)} s</Text>
            <Text>Duración: {(outcome.result.durationMs / 1000).toFixed(2)} s</Text>
            <Text>Tamaño: {(outcome.result.sizeBytes / 1024).toFixed(0)} KB</Text>
            <Text>
              {outcome.result.sampleRate} Hz · {outcome.result.channels} canal(es) ·{' '}
              {outcome.result.bitrate} kbps
            </Text>
            <Text style={styles.muted} selectable>
              {outcome.result.uri}
            </Text>
          </View>
        )}
        {outcome?.kind === 'error' && (
          <View style={styles.card}>
            <Text style={styles.error}>{outcome.code}</Text>
            <Text style={styles.muted}>{outcome.message}</Text>
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function Button(props: { label: string; onPress: () => void; disabled?: boolean }) {
  return (
    <Pressable
      onPress={props.onPress}
      disabled={props.disabled}
      style={[styles.button, props.disabled && styles.buttonDisabled]}>
      <Text style={styles.buttonText}>{props.label}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: '#fff' },
  content: { padding: 20, gap: 12 },
  title: { fontSize: 24, fontWeight: '700', marginBottom: 8 },
  label: { fontWeight: '600', marginTop: 8 },
  muted: { color: '#666' },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  chip: { paddingVertical: 6, paddingHorizontal: 12, borderRadius: 16, borderWidth: 1, borderColor: '#ccc' },
  chipActive: { backgroundColor: '#222', borderColor: '#222' },
  chipTextActive: { color: '#fff' },
  button: { backgroundColor: '#222', padding: 14, borderRadius: 10, alignItems: 'center' },
  buttonDisabled: { opacity: 0.4 },
  buttonText: { color: '#fff', fontWeight: '600' },
  spinner: { marginTop: 8 },
  card: { padding: 14, borderRadius: 10, backgroundColor: '#f3f3f3', gap: 4 },
  ok: { fontWeight: '700', color: '#1a7f37' },
  error: { fontWeight: '700', color: '#c62828' },
});
