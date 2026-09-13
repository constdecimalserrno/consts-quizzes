import struct, zlib
NAVY=(0x08,0x0C,0x33); GOLD=(0xFF,0xC1,0x2B); MAGENTA=(0xFF,0x2E,0x88)
CYAN=(0x35,0xE0,0xF2); SCREEN=(0x14,0x1B,0x5C); BEVEL=(0x00,0x05,0x1F)

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
    # The set itself: a television that is on. The old mark was four podiums,
    # which at sixteen pixels is four squares and reads as a loading state; a
    # lit screen says what the thing is — a broadcast that never stops.
    if size >= 128:
        rect(2.9, 3.9, 22.9, 18.9, BEVEL)          # the bevel under the set
    rect(2, 3, 22, 18, GOLD)                        # the frame
    rect(4, 5, 20, 16, SCREEN)                      # the glass
    # On the glass: the four Choices, one of them lit. Three bars alone read
    # as a list icon; four blocks with one picked out reads as the game being
    # played, which is the point — a quiz, on air.
    for i in range(2):
        for j in range(2):
            x = 5.6 + i*7.0
            y = 6.4 + j*4.8
            rect(x, y, x+6.2, y+3.6, MAGENTA if (i,j)==(1,1) else CYAN)
    rect(9.5, 18, 14.5, 21, GOLD)                   # the stand
    return buf

for n,s,i in [('favicon-32.png',32,0.0),('Icon-192.png',192,0.0),('Icon-512.png',512,0.0),
              ('Icon-maskable-192.png',192,0.20),('Icon-maskable-512.png',512,0.20)]:
    png(n,s,draw(s,i))
print('ok')
