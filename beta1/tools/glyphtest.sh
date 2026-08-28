#!/bin/sh
# Exercise every glyph, from a machine PTERM has ssh-d into.
#
# THE CHARACTERS ARE LITERAL, not printf \x escapes. dash's printf does not
# understand \xNN, so the escaped version printed its own escapes under
# /bin/sh and only worked when run with bash - which is not what the shebang
# on this file says.
# Nothing here should print a question mark. That is the test: '?' is what
# FBVDU draws for a codepoint it has no glyph for, so one is a real gap.
#
#   sh glyphtest.sh
#
# The three boxes are not decoration. Between them they use all 29 double
# box-drawing characters, and every join in them is a MATCHED join - a double
# arm meeting a double arm, a single meeting a single. So a wrong glyph does
# not look slightly off, it breaks the box where it sits.

# All 29 double box characters and all 32 block elements, each in a place
# where every join is correct. If a glyph is wrong the box breaks visibly.
printf '\n all double            double stem           double rail\n'
printf ' %s\n' '╔══╦══╗      ╓──╥──╖      ╒══╤══╕'
printf ' %s\n' '║  ║  ║      ║  ║  ║      │  │  │'
printf ' %s\n' '╠══╬══╣      ╟──╫──╢      ╞══╪══╡'
printf ' %s\n' '║  ║  ║      ║  ║  ║      │  │  │'
printf ' %s\n' '╚══╩══╝      ╙──╨──╜      ╘══╧══╛'
printf '\n eighths, a smooth ramp one pixel taller each step\n'
printf ' %s\n' '▁▂▃▄▅▆▇█   and sideways ▏▎▍▌▋▊▉█'
printf '\n halves and quadrants, then the shades\n'
printf ' %s\n' '▀▄▌▐▔▕   ▖▗▘▙▚▛▜▝▞▟   ░▒▓█'
printf '\n'
printf '\n latin-1, most of it composed from this font own letters\n'
printf ' %s\n' ' ¡¢£¤¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿'
printf ' %s\n' 'ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖ×ØÙÚÛÜÝÞß'
printf ' %s\n' 'àáâãäåæçèéêëìíîïðñòóôõö÷øùúûüýþÿ'
printf '\n sextants, all 60\n'
printf ' %s\n' '🬀🬁🬂🬃🬄🬅🬆🬇🬈🬉🬊🬋🬌🬍🬎🬏🬐🬑🬒🬓🬔🬕🬖🬗🬘🬙🬚🬛🬜🬝🬞🬟🬠🬡🬢🬣🬤🬥🬦🬧🬨🬩🬪🬫🬬🬭🬮🬯🬰🬱🬲🬳🬴🬵🬶🬷🬸🬹🬺🬻'
printf '\n legacy diagonals and eighths, all 80\n'
printf ' %s\n' '🬼🬽🬾🬿🭀🭁🭂🭃🭄🭅🭆🭇🭈🭉🭊🭋🭌🭍🭎🭏🭐🭑🭒🭓🭔🭕🭖🭗🭘🭙🭚🭛🭜🭝🭞🭟🭠🭡🭢🭣'
printf ' %s\n' '🭤🭥🭦🭧🭨🭩🭪🭫🭬🭭🭮🭯🭰🭱🭲🭳🭴🭵🭶🭷🭸🭹🭺🭻🭼🭽🭾🭿🮀🮁🮂🮃🮄🮅🮆🮇🮈🮉🮊🮋'
printf '\n octants, all 230 - a solid ramp, no gaps and no question marks\n'
printf ' %s\n' '𜴀𜴁𜴂𜴃𜴄𜴅𜴆𜴇𜴈𜴉𜴊𜴋𜴌𜴍𜴎𜴏𜴐𜴑𜴒𜴓𜴔𜴕𜴖𜴗𜴘𜴙𜴚𜴛𜴜𜴝𜴞𜴟𜴠𜴡𜴢𜴣𜴤𜴥𜴦𜴧𜴨𜴩𜴪𜴫𜴬𜴭𜴮𜴯𜴰𜴱𜴲𜴳𜴴𜴵𜴶𜴷𜴸𜴹𜴺𜴻𜴼𜴽𜴾𜴿𜵀𜵁𜵂𜵃𜵄𜵅𜵆𜵇𜵈𜵉𜵊𜵋𜵌'
printf ' %s\n' '𜵍𜵎𜵏𜵐𜵑𜵒𜵓𜵔𜵕𜵖𜵗𜵘𜵙𜵚𜵛𜵜𜵝𜵞𜵟𜵠𜵡𜵢𜵣𜵤𜵥𜵦𜵧𜵨𜵩𜵪𜵫𜵬𜵭𜵮𜵯𜵰𜵱𜵲𜵳𜵴𜵵𜵶𜵷𜵸𜵹𜵺𜵻𜵼𜵽𜵾𜵿𜶀𜶁𜶂𜶃𜶄𜶅𜶆𜶇𜶈𜶉𜶊𜶋𜶌𜶍𜶎𜶏𜶐𜶑𜶒𜶓𜶔𜶕𜶖𜶗𜶘𜶙'
printf ' %s\n' '𜶚𜶛𜶜𜶝𜶞𜶟𜶠𜶡𜶢𜶣𜶤𜶥𜶦𜶧𜶨𜶩𜶪𜶫𜶬𜶭𜶮𜶯𜶰𜶱𜶲𜶳𜶴𜶵𜶶𜶷𜶸𜶹𜶺𜶻𜶼𜶽𜶾𜶿𜷀𜷁𜷂𜷃𜷄𜷅𜷆𜷇𜷈𜷉𜷊𜷋𜷌𜷍𜷎𜷏𜷐𜷑𜷒𜷓𜷔𜷕𜷖𜷗𜷘𜷙𜷚𜷛𜷜𜷝𜷞𜷟𜷠𜷡𜷢𜷣𜷤𜷥'
printf '\n the odds and ends\n'
printf ' %s\n' 'ƒ΄Γφⁿ√∞∩≈≡⌂⌐⌠⎺⎻⎼⎽━╼╾►◄●⟨⟩'
printf '\n'
