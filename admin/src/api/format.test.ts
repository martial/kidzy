import { describe, expect, it } from 'vitest'
import { formatBytes, formatDuration } from './format'

describe('formatDuration', () => {
  it('formats seconds, minutes and hours', () => {
    expect(formatDuration(42)).toBe('42 s')
    expect(formatDuration(125)).toBe('2 min 05 s')
    expect(formatDuration(3725)).toBe('1 h 02 min')
  })
})

describe('formatBytes', () => {
  it('picks the unit', () => {
    expect(formatBytes(900)).toBe('900 o')
    expect(formatBytes(1536)).toBe('1.5 Ko')
    expect(formatBytes(3 * 1024 ** 3)).toBe('3.0 Go')
  })
})
