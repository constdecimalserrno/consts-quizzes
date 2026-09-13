import struct, zlib
NAVY=(0x08,0x0C,0x33); GOLD=(0xFF,0xC1,0x2B); MAGENTA=(0xFF,0x2E,0x88)
BEVEL=(0x00,0x05,0x1F)

def png(path,size,px):
    raw=b''.join(b'\x00'+bytes(v for p in row for v in p) for row in px)
    ch=lambda t,d: struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d))
    open(path,'wb').write(b'\x89PNG\r\n\x1a\n'
        +ch(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))
        +ch(b'IDAT',zlib.compress(raw,9))+ch(b'IEND',b''))

def draw(size, inset=0.0):
    u=size/24.0
    buf=[[NAVY]*size for _ in range(size)]
    def rect(x1,y1,x2,y2,c):
        s=1.0-inset
        f=lambda x,y:((x-12)*s+12,(y-12)*s+12)
        (ax,ay),(bx,by)=f(x1,y1),f(x2,y2)
        for py in range(max(0,int(ay*u)),min(size,int(by*u+0.5))):
            for px in range(max(0,int(ax*u)),min(size,int(bx*u+0.5))):
                buf[py][px]=c
    # The game's own four podiums, one of them the answer. Four blocks survive
    # sixteen pixels in a way a question mark does not.
    gap, edge = 1.6, 4.0
    span = (24 - edge*2 - gap) / 2
    for i in range(2):
        for j in range(2):
            x = edge + i*(span+gap)
            y = edge + j*(span+gap)
            colour = MAGENTA if (i, j) == (1, 1) else GOLD
            # The podium bevel, where there is room for it. At favicon size a
            # one-pixel shadow is dirt on the glass.
            if size >= 128:
                rect(x+0.7, y+0.7, x+span+0.7, y+span+0.7, BEVEL)
            rect(x, y, x+span, y+span, colour)
    return buf

for n,s,i in [('favicon-32.png',32,0.0),('Icon-192.png',192,0.0),('Icon-512.png',512,0.0),
              ('Icon-maskable-192.png',192,0.18),('Icon-maskable-512.png',512,0.18)]:
    png(n,s,draw(s,i))
print('ok')
