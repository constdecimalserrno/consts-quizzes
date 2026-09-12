/**
 * Handle minting: `emotion-color-animal-NNN`.
 *
 * The three lists below are the whole of the namespace's vocabulary; the
 * three-digit model number is what makes the space big enough that collisions
 * stay rare — 141 x 135 x 175 x 900 is about 3.0 billion.
 *
 * Words are lowercase ASCII, no list shares a word with another (`salmon` is a
 * colour here and not a fish), and every one has to survive being somebody's
 * public name next to any two of the others. Add words; never remove one — a
 * Handle already minted stays reserved either way, but a word that leaves the
 * list turns every page it appears on into a typo.
 */

const HANDLE_EMOTIONS: readonly string[] = [
  'grumpy', 'jolly', 'sleepy', 'feisty', 'mellow', 'rowdy', 'sassy',
  'chill', 'peppy', 'moody', 'zesty', 'dizzy', 'perky', 'salty', 'breezy',
  'giddy', 'bashful', 'bold', 'bouncy', 'brave', 'bubbly', 'calm', 'cheery',
  'chirpy', 'clever', 'cozy', 'crafty', 'cranky', 'curious', 'dapper',
  'daring', 'dreamy', 'eager', 'fancy', 'fiery', 'fluffy', 'foggy',
  'frisky', 'frosty', 'gentle', 'gloomy', 'goofy', 'groovy', 'grouchy',
  'gutsy', 'hasty', 'hearty', 'humble', 'hungry', 'jaunty', 'jittery',
  'jovial', 'jumpy', 'keen', 'lanky', 'lazy', 'lively', 'lofty', 'loopy',
  'lucky', 'merry', 'mighty', 'mopey', 'nifty', 'nimble', 'nosy', 'patient',
  'pesky', 'playful', 'plucky', 'pouty', 'prickly', 'proud', 'punchy',
  'quirky', 'restless', 'scrappy', 'scruffy', 'shaky', 'sneaky', 'snappy',
  'snoozy', 'snug', 'spiffy', 'spooky', 'spunky', 'squeaky', 'steady',
  'stormy', 'sturdy', 'sulky', 'sunny', 'swanky', 'thrifty', 'touchy',
  'tricky', 'twitchy', 'upbeat', 'wacky', 'weary', 'wiggly', 'wistful',
  'witty', 'wobbly', 'zany', 'zealous', 'zippy', 'antsy', 'bleary', 'brisk',
  'cheeky', 'dozy', 'frantic', 'hyper', 'jaded', 'loyal', 'nervous',
  'peachy', 'rascal', 'sprightly', 'plush', 'hardy', 'rugged', 'tidy',
  'bright', 'chipper', 'sleek', 'grateful', 'hopeful', 'earnest', 'serene',
  'mindful', 'gallant', 'valiant', 'noble', 'jazzy', 'funky', 'rusty',
  'dusty', 'misty', 'balmy',
]

const HANDLE_COLORS: readonly string[] = [
  'teal', 'crimson', 'amber', 'indigo', 'olive', 'coral', 'navy', 'maroon',
  'violet', 'copper', 'jade', 'scarlet', 'slate', 'ivory', 'golden',
  'silver', 'azure', 'beige', 'bronze', 'burgundy', 'cerulean', 'cherry',
  'chestnut', 'cobalt', 'cocoa', 'cream', 'cyan', 'denim', 'ebony',
  'emerald', 'fuchsia', 'garnet', 'ginger', 'hazel', 'honey', 'khaki',
  'lavender', 'lemon', 'lilac', 'lime', 'magenta', 'mahogany', 'mango',
  'mauve', 'mint', 'mocha', 'mustard', 'ochre', 'onyx', 'orange', 'orchid',
  'peach', 'pearl', 'pewter', 'pine', 'plum', 'pumpkin', 'quartz', 'rose',
  'ruby', 'ruddy', 'rust', 'saffron', 'sage', 'salmon', 'sand', 'sapphire',
  'sepia', 'sienna', 'smoky', 'steel', 'tan', 'taupe', 'topaz', 'umber',
  'walnut', 'wheat', 'yellow', 'blue', 'green', 'red', 'pink', 'purple',
  'brown', 'gray', 'black', 'white', 'gold', 'ash', 'brass', 'clay',
  'cinnamon', 'berry', 'flame', 'ocean', 'forest', 'moss', 'dusk', 'dawn',
  'ink', 'tawny', 'aqua', 'blush', 'fern', 'glacier', 'iris', 'jasper',
  'marigold', 'opal', 'poppy', 'sky', 'snow', 'storm', 'sunset', 'midnight',
  'charcoal', 'apricot', 'avocado', 'butter', 'caramel', 'carrot', 'citron',
  'eggplant', 'grape', 'hibiscus', 'iron', 'jet', 'marble', 'nickel',
  'papaya', 'platinum', 'seafoam', 'shamrock', 'tomato', 'zinc',
]

const HANDLE_ANIMALS: readonly string[] = [
  'walrus', 'badger', 'falcon', 'otter', 'moose', 'gecko', 'bison', 'heron',
  'lynx', 'marmot', 'pelican', 'wombat', 'ferret', 'osprey', 'newt',
  'stoat', 'alpaca', 'antelope', 'axolotl', 'baboon', 'beagle', 'bear',
  'beetle', 'bobcat', 'buffalo', 'bulldog', 'bunny', 'camel', 'caribou',
  'cheetah', 'chicken', 'chipmunk', 'cobra', 'condor', 'corgi', 'coyote',
  'crab', 'crane', 'cricket', 'crow', 'dingo', 'dolphin', 'donkey', 'dove',
  'dragon', 'duck', 'eagle', 'eel', 'egret', 'elk', 'emu', 'finch',
  'firefly', 'flamingo', 'fox', 'frog', 'gazelle', 'gibbon', 'giraffe',
  'goat', 'goose', 'gopher', 'gorilla', 'grizzly', 'hamster', 'hawk',
  'hedgehog', 'hippo', 'hornet', 'horse', 'hound', 'husky', 'hyena', 'ibex',
  'ibis', 'iguana', 'impala', 'jackal', 'jaguar', 'jay', 'kestrel', 'koala',
  'kiwi', 'lemur', 'leopard', 'lion', 'lizard', 'llama', 'lobster', 'macaw',
  'magpie', 'manatee', 'mantis', 'meerkat', 'mole', 'mongoose', 'monkey',
  'moth', 'mouse', 'mule', 'narwhal', 'ocelot', 'octopus', 'orca', 'oriole',
  'ostrich', 'owl', 'panda', 'panther', 'parrot', 'penguin', 'pig',
  'pigeon', 'piranha', 'platypus', 'pony', 'poodle', 'possum', 'puffin',
  'puma', 'python', 'quail', 'quokka', 'rabbit', 'raccoon', 'ram', 'rhino',
  'robin', 'rooster', 'seal', 'shark', 'sheep', 'shrimp', 'skunk', 'sloth',
  'snail', 'sparrow', 'spider', 'squid', 'squirrel', 'stag', 'stork',
  'swan', 'tapir', 'tiger', 'toad', 'toucan', 'trout', 'turkey', 'turtle',
  'viper', 'vulture', 'wallaby', 'weasel', 'whale', 'wolf', 'yak', 'zebra',
  'bat', 'bee', 'cod', 'cat', 'dog', 'gnat', 'gull', 'hare', 'koi', 'lark',
  'mink', 'pike', 'wren', 'goldfish', 'terrier', 'collie', 'mastiff',
]

/** Shape of a Handle, used to tell a generated one from anything else. */
export const HANDLE_PATTERN = /^[a-z]+-[a-z]+-[a-z]+-\d{3}$/

export const isHandle = (v: unknown): v is string =>
  typeof v === 'string' && HANDLE_PATTERN.test(v)

export function randomHandle(): string {
  const pick = (list: readonly string[]) =>
    list[Math.floor(Math.random() * list.length)]!
  return [
    pick(HANDLE_EMOTIONS),
    pick(HANDLE_COLORS),
    pick(HANDLE_ANIMALS),
    100 + Math.floor(Math.random() * 900),
  ].join('-')
}
