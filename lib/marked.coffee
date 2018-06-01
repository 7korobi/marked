# Helpers

escape = (html, encode) ->
  amp =
    if encode
    then /&/g
    else /&(?!#?\w+;)/g
  html
  .replace amp,  '&amp;'
  .replace /</g, '&lt;'
  .replace />/g, '&gt;'
  .replace /"/g, '&quot;'
  .replace /'/g, '&#39;'

unescape = (html) ->
  # explicitly match decimal, hex, and named HTML entities
  html.replace /&(#(?:\d+)|(?:#x[0-9A-Fa-f]+)|(?:\w+));?/ig, (_, n) ->
    n = n.toLowerCase()
    if n == 'colon'
      return ':'
    if n.charAt(0) == '#'
      if n.charAt(1) == 'x'
        String.fromCharCode parseInt n[2..], 16
      else
        String.fromCharCode parseInt n[1..]
    else
      ''

resolveUrl = (base, href)->
  key = ' ' + base
  if ! baseUrls[key]
    # we can ignore everything in base after the last slash of its path component,
    # but we might need to add _that_
    # https://tools.ietf.org/html/rfc3986#section-3
    if /^[^:]+:\/*[^/]*$/.test(base)
      baseUrls[key] = base + '/'
    else
      baseUrls[key] = base.replace(/[^/]*$/, '')

  base = baseUrls[key]

  switch
    when href[0..1] == '//'
      base.replace(/:[\s\S]*/, ':') + href
    when href.charAt(0) == '/'
      base.replace(/(:\/*[^/]*)[\s\S]*/, '$1') + href
    else
      base + href

splitCells = (tableRow, count)->
  cells = tableRow.replace(/([^\\])\|/g, '$1 |').split(/ +\| */)
  i = 0

  if cells.length > count
    cells.splice count
  else
    while cells.length < count
      cells.push ''

  for o, i in cells
    cells[i] = o.replace(/\\\|/g, '|')
  cells


baseUrls = {}
originIndependentUrl = /^$|^[a-z][a-z0-9+.-]*:|^[?#]/i

noop = ->
noop.exec = noop

replace = (regex, opt) ->
  regex = regex.source or regex
  opt = opt or ''
  self = (name, val) ->
    if !name
      return new RegExp(regex, opt)
    val = val.source or val
    val = val.replace(/(^|[^\[])\^/g, '$1')
    regex = regex.replace(name, val)
    self
  self

###
# Block Lexer
###
block =
  newline: /^ *\n+/
  code: /^( {4}[^\n]+\n*)+/
  fences: noop
  hr: /^ {0,3}((?:- *){3,}|(?:_ *){3,}|(?:\* *){3,})(?:\n|$)/
  heading: /^ *(#{1,6}) *([^\n]+?) *(?:#+ *)?(?:\n|$)/
  nptable: noop
  blockquote: /^( {0,3}> ?(paragraph|[^\n]*)(?:\n|$))+/
  list: /^( *)(bull) [\s\S]+?(?:hr|def|\n{2,}(?! )(?!\1bull )\n*|\s*$)/
  checkbox: /^\[([ xX])\] +/
  html: ///
    ^\ {0,3}(?: # optional indentation
    <(script|pre|style)[\s>][\s\S]*?(?:</\1>[^\n]*\n+|$) # (1)
    |comment[^\n]*(\n+|$) # (2)
    |<\?[\s\S]*?\?>\n* # (3)
    |<![A-Z][\s\S]*?>\n* # (4)
    |<!\[CDATA\[[\s\S]*?\]\]>\n* # (5)
    |</?(tag)(?:\ +|\n|/?>)[\s\S]*?(?:\n{2,}|$) # (6)
    |<(?!script|pre|style)([a-z][\w-]*)(?:attribute)*?\ */?>(?=\h*\n)[\s\S]*?(?:\n{2,}|$) # (7) open tag
    |</(?!script|pre|style)[a-z][\w-]*\s*>(?=\h*\n)[\s\S]*?(?:\n{2,}|$) # (7) closing tag
    )
  ///
  def: /^ {0,3}\[(label)\]: *\n? *<?([^\s>]+)>?(?:(?: +\n? *| *\n *)(title))? *(?:\n|$)/
  table: noop
  lheading: /^([^\n]+)\n *(=|-){2,} *(?:\n|$)/
  paragraph: /^([^\n]+(?:\n(?!hr|heading|lheading| {0,3}>|<\/?(?:tag)(?: +|\n|\/?>)|<(?:script|pre|style|!--))[^\n]+)*)/
  text: /^[^\n]+/

block._label = /(?!\s*\])(?:\\[\[\]]|[^\[\]])+/
block._title = /(?:"(?:\\"?|[^"\\])*"|'[^'\n]*(?:\n[^'\n]+)*\n?'|\([^()]*\))/
block.def = replace(block.def
)( 'label', block._label
)( 'title', block._title
)()

block.with_bullet = /^ *([*+-]|\d+\.) +/
block.bullet = /(?:[*+-]|\d+\.)/
block.item = /^( *)(bull) [^\n]*(?:\n(?!\1bull )[^\n]*)*/
block.item = replace(block.item, 'gm'
)( /bull/g, block.bullet
)()

block.list = replace(block.list
)( /bull/g, block.bullet
)( 'hr', '\\n+(?=\\1?(?:(?:- *){3,}|(?:_ *){3,}|(?:\\* *){3,})(?:\\n|$))'
)( 'def', '\\n+(?=' + block.def.source + ')'
)()

block._tag = ///
  address|article|aside|base|basefont|blockquote|body|caption
  |center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption
  |figure|footer|form|frame|frameset|h[1-6]|head|header|hr|html|iframe
  |legend|li|link|main|menu|menuitem|meta|nav|noframes|ol|optgroup|option
  |p|param|section|source|summary|table|tbody|td|tfoot|th|thead|title|tr
  |track|ul
///

block._comment = /<!--(?!-?>)[\s\S]*?-->/
block.html = replace(block.html, 'i'
)( 'comment', block._comment
)( 'tag', block._tag
)('attribute', / +[a-zA-Z:_][\w.:-]*(?: *= *"[^"\n]*"| *= *'[^'\n]*'| *= *[^\s"'=<>`]+)?/
)()

block.paragraph = replace(block.paragraph
)( 'hr', block.hr
)( 'heading', block.heading
)( 'lheading', block.lheading
)( 'tag', block._tag
)()

block.blockquote = replace(block.blockquote
)( 'paragraph', block.paragraph
)()

###
# Normal Block Grammar
###
block.normal = Object.assign {}, block

###
# GFM Block Grammar
###
block.gfm = Object.assign {}, block.normal,
  fences: /^ *(`{3,}|~{3,})[ \.]*(\S+)? *\n([\s\S]*?)\n? *\1 *(?:\n|$)/
  paragraph: /^/
  heading: /^ *(#{1,6}) +([^\n]+?) *#* *(?:\n|$)/

block.gfm.paragraph = replace(block.paragraph
)( '(?!', "(?!#{
  block.gfm.fences.source.replace('\\1', '\\2')
}|#{
  block.list.source.replace('\\1', '\\3')
}|"
)()

###
# GFM + Tables Block Grammar
###
block.tables = Object.assign {}, block.gfm,
  nptable: /^ *([^|\n ].*\|.*)\n *([-:]+ *\|[-| :]*)(?:\n((?:.*[^>\n ].*(?:\n|$))*)\n*|$)/
  table: /^ *\|(.+)\n *\|?( *[-:]+[-| :]*)(?:\n((?: *[^>\n ].*(?:\n|$))*)\n*|$)/


class Lexer
  @rules: block
  @lex: (src, options) ->
    new Lexer(options).lex(src)

  constructor: (@options)->
    @tokens = []
    @tokens.notes = []
    @tokens.links = {}
    @rules = block.normal
    if @options.gfm
      @rules =
        if @options.tables
        then block.tables
        else block.gfm

  lex: (src) ->
    src = src
    .replace /\r\n|\r/g, '\n'
    .replace /\t/g, '    '
    .replace /\u00a0/g, ' '
    .replace /\u2424/g, '\n'
    @token src, true

  token: (src, top) ->
    while src
      # newline
      if cap = @rules.newline.exec src
        src = src[cap[0].length ..]
        if cap[0].length
          @tokens.push
            type: 'space'
            text: cap[0]

      # code
      if @options.indentCode && cap = @rules.code.exec src
        # console.log 'block code', cap
        src = src[cap[0].length ..]
        cap = cap[0].replace /^ {4}/gm, ''
        @tokens.push
          type: 'code'
          text: cap
        continue

      # fences (gfm)
      if cap = @rules.fences.exec src
        # console.log 'block fences', cap
        src = src[cap[0].length ..]
        @tokens.push
          type: 'code'
          lang: cap[2]
          text: cap[3] or ''
        continue

      # heading
      if cap = @rules.heading.exec src
        # console.log 'block heading', cap
        src = src[cap[0].length ..]
        @tokens.push
          type: 'heading'
          depth: cap[1].length
          text: cap[2]
        continue

      # table no leading pipe (gfm)
      if top and cap = @rules.nptable.exec src
        src = src[cap[0].length ..]
        item =
          type: 'table'
          header: splitCells cap[1].replace(/^ *| *\| *$/g, '')
          align: cap[2].replace(/^ *|\| *$/g, '').split(/ *\| */)
          cells: cap[3]?.replace(/\n$/, '').split('\n') || []
        for o, i in item.align
          item.align[i] =
            if      /^ *-+: *$/.test o  then 'right'
            else if /^ *:-+: *$/.test o then 'center'
            else if /^ *:-+ *$/.test o  then 'left'
            else                              null
        for o, i in item.cells
          item.cells[i] = splitCells o, item.header.length
        @tokens.push item
        continue

      # hr
      if cap = @rules.hr.exec src
        # console.log 'block hr', cap
        src = src[cap[0].length ..]
        @tokens.push type: 'hr'
        continue

      # blockquote
      if cap = @rules.blockquote.exec src
        src = src[cap[0].length ..]
        @tokens.push
          type: 'blockquote_start'
        cap = cap[0].replace /^ *> ?/gm, ''
        # Pass `top` to keep the current
        # "toplevel" state. This is exactly
        # how markdown.pl works.
        @token cap, top, true
        @tokens.push
          type: 'blockquote_end'
        continue

      # list
      if cap = @rules.list.exec src
        # console.log 'block list', cap
        src = src[cap[0].length ..]
        bull = cap[2]
        is_ordered = "." == bull.slice(-1)
        @tokens.push
          type: 'list_start'
          ordered: is_ordered
          start:
            if is_ordered
            then  +bull
            else  ''
        # Get each top-level item.
        cap = cap[0].match(@rules.item)
        next = false

        l = cap.length
        i = 0
        while i < l
          item = cap[i]
          # Remove the list item's bullet
          # so it is seen as the next token.
          space = item.length
          item = item.replace @rules.with_bullet, ''

          # Outdent whatever the
          # list item contains. Hacky.
          if ~item.indexOf('\n ')
            space -= item.length
            item = item.replace(///^\ {1,#{ space }}///gm, '')

          # Determine whether the next list item belongs here.
          # Backpedal if it does not belong in this list.
          if @options.smartLists and i != l - 1
            b = block.bullet.exec(cap[i + 1])[0]
            if bull != b and !(bull.length > 1 and b.length > 1)
              src = cap[i + 1 ..].join('\n') + src
              i = l - 1

          # Determine whether item is loose or not.
          # Use: /(^|\n)(?! )[^\n]+\n\n(?!\s*$)/
          # for discount behavior.
          loose = next or /\n\n(?!\s*$)/.test(item)
          if i != l - 1
            next = item.charAt(item.length - 1) == '\n'
            if !loose
              loose = next

          # Check for task list items
          checkbox = @rules.checkbox.exec item
          checked =
            if checkbox
              item = item.replace @rules.checkbox, ''
              checkbox[1] != ' '

          type = if loose then 'loose_item_start' else 'list_item_start'
          @tokens.push { checked, type, task: checked? }

          # Recurse.
          @token item, false
          @tokens.push type: 'list_item_end'
          i++
        @tokens.push type: 'list_end'
        continue

      # html
      if cap = @rules.html.exec src
        src = src[cap[0].length ..]
        @tokens.push
          type:
            if @options.sanitize
            then 'paragraph'
            else 'html'
          pre: !@options.sanitizer and cap[1] in ['pre', 'script', 'style']
          text: cap[0]
        continue

      # def
      if top and cap = @rules.def.exec src
        # console.log 'def', cap
        src = src[cap[0].length ..]
        if cap[3]
          cap[3] = cap[3][1...-1]
        tag = cap[1].toLowerCase()
        @tokens.links[tag] ||=
          href:  cap[2]
          title: cap[3]
        continue

      # table (gfm)
      if top and cap = @rules.table.exec src
        item =
          type: 'table'
          header: splitCells cap[1].replace(/^ *| *\| *$/g, '')
          align: cap[2].replace(/^ *|\| *$/g, '').split(/ *\| */)
          cells:
            if cap[3]
            then  cap[3].replace(/(?: *\| *)?\n$/, '').split('\n')
            else  []
        if item.header.length == item.align.length
          src = src[cap[0].length ..]
          for o, i in item.align
            item.align[i] =
              if      /^ *-+: *$/.test(o)  then 'right'
              else if /^ *:-+: *$/.test(o) then 'center'
              else if /^ *:-+ *$/.test(o)  then 'left'
              else                               null
          for o, i in item.cells
            item.cells[i] = splitCells o.replace(/^ *\| *| *\| *$/g, ''), item.header.length
          @tokens.push item
          continue

      # lheading
      if cap = @rules.lheading.exec src
        src = src[cap[0].length ..]
        @tokens.push
          type: 'heading'
          depth:
            if cap[2] == '='
            then 1
            else 2
          text: cap[1]
        continue
 
      # top-level paragraph
      if top and cap = @rules.paragraph.exec src
        src = src[cap[0].length ..]
        @tokens.push
          type: 'paragraph'
          text: cap[0]
        continue

      # text
      if cap = @rules.text.exec src
        # Top-level should never reach here.
        src = src[cap[0].length ..]
        @tokens.push
          type: 'text'
          text: cap[0]
          top: top
        continue

      if src
        throw new Error('Infinite loop on byte: ' + src.charCodeAt(0))
    @tokens


###
# Inline-Level Grammar
###
inline =
  escape: /^\\([!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~])/
  autolink: /^<(scheme:[^\s\x00-\x1f<>]*|email)>/
  url: noop
  tag: ///
     ^comment
    |^</[a-zA-Z][\w:-]*\s*>                # self-closing tag
    |^<[a-zA-Z][\w-]*(?:attribute)*?\s*/?> # open tag
    |^<\?[\s\S]*?\?>                       # processing instruction, e.g. <?php ?>
    |^<![a-zA-Z]+\s[\s\S]*?>               # declaration, e.g. <!DOCTYPE html>
    |^<!\[CDATA\[[\s\S]*?\]\]>             # CDATA section
  ///

  link: /^!?\[(label)\]\(href(?:\s+(title))?\s*\)/
  reflink: ///
    ^!?\[(label)\]\[(?!\s*\])((?:
       \\[\[\]]?
      |[^\[\]\\]
    )+)\]
  ///
  nolink: ///
    ^!?\[(?!\s*\])((?:
       \[[^\[\]]*\]
      |\\[\[\]]
      |[^\[\]]
    )*)\](?:\[\])?
  ///
  strong: ///
    ^([_~*=])\1(
       [^\s][\s\S]*?[^\s]
      |[^\s]
    )\1\1(?!\1)
  ///
  em: ///
     ^_([^\s][\s\S]*?[^\s_])_(?!_)
    |^_([^\s_][\s\S]*?[^\s])_(?!_)
    |^\*([^\s][\s\S]*?[^\s*])\*(?!\*)
    |^\*([^\s*][\s\S]*?[^\s])\*(?!\*)
    |^_([^\s_])_(?!_)
    |^\*([^\s*])\*(?!\*)
  ///
  code: /^(`+)\s*([\s\S]*?[^`]?)\s*\1(?!`)/
  br: /^ {2,}\n(?!\s*$)/
  text: /^[\s\S]+?(?=[\\<!\[`*-=]|\b_| {2,}\n|$)/

  # extended
  anker: /^\w+-\w+-\w+-\w+-\w+|-\w+-\w+-\w+-\w+|-\w+-\w+-\w+|-\w+-\w+/
  note: /^\^\[(label)\]/
  sup: /^\^((?:[^\s^]|\^\^)+?)\^(?!\^)/
  sub: /^~((?:[^\s~]|~~)+?)~(?!~)/


  _escapes: /\\([!"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~])/g
  _scheme: /[a-zA-Z][a-zA-Z0-9+.-]{1,31}/
  _email: ///
    [a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+
    (@)
    [a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
    (?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+
    (?![-_])
  ///

  _attribute: /\s+[a-zA-Z:_][\w.:-]*(?:\s*=\s*"[^"]*"|\s*=\s*'[^']*'|\s*=\s*[^\s"'=<>`]+)?/
  _label: /(?:\[[^\[\]]*\]|\\[\[\]]?|`[^`]*`|[^\[\]\\])*?/
  _href: ///
    \s*(
      <(?:\\[<>]?
      |[^\s<>\\])*>
      |(?:\\[()]?
      |\([^\s\x00-\x1f()\\]*\)
      |[^\s\x00-\x1f()\\]
    )*?)
  ///
  _title: /"(?:\\"?|[^"\\])*"|'(?:\\'?|[^'\\])*'|\((?:\\\)?|[^)\\])*\)/



inline.autolink = replace(inline.autolink
)('scheme', inline._scheme
)('email', inline._email
)()

inline.tag = replace(inline.tag
)('comment', block._comment
)('attribute', inline._attribute
)()

inline.link = replace(inline.link
)('label', inline._label
)('href', inline._href
)('title', inline._title
)()

inline.reflink = replace(inline.reflink
)('label', inline._label
)()

inline.note = replace(inline.note
)('label', inline._label
)()

###
# Normal Inline Grammar
###
inline.normal = Object.assign({}, inline)

###
# Pedantic Inline Grammar
# -- bye --
###

###
# GFM Inline Grammar
###
inline.gfm = Object.assign({}, inline.normal,
  escape: replace(inline.escape)('])', '~|])')()
  text: replace(inline.text)(']|', '~]|')('|', '|https?://|ftp://|www\\.|[a-zA-Z0-9.!#$%&\'*+/=?^_`{\\|}~-]+@|')()
  url: replace(/^((?:ftp|https?):\/\/|www\.)(?:[a-zA-Z0-9\-]+\.?)+[^\s<]*|^email/)('email', inline._email)()

  _backpedal: /(?:[^?!.,:;*_~()&]+|\([^)]*\)|&(?![a-zA-Z0-9]+;$)|[?!.,:;*_~)]+(?!$))+/
)

###
# GFM + Line Breaks Inline Grammar
###
inline.breaks = Object.assign({}, inline.gfm,
  br: replace(inline.br)('{2,}', '*')()
  text: replace(inline.gfm.text)('{2,}', '*')())

###
# Inline Lexer & Compiler
###
class InlineLexer
  ###
  # Expose Inline Rules
  ###
  @rules: inline
  @output: (src, options) ->
    new InlineLexer(options, options).output src

  @escapes: (text)->
    text?.replace(InlineLexer.rules._escapes, '$1') or text

  constructor: ({ @notes, @links }, options) ->
    @options = options or marked.defaults
    @rules = inline.normal
    @renderer = @options.renderer or new Renderer
    @renderer.options = @options
    if !@notes
      throw new Error('Tokens array requires a `notes` property.')
    if !@links
      throw new Error('Tokens array requires a `links` property.')
    if @options.gfm
      if @options.breaks
        @rules = inline.breaks
      else
        @rules = inline.gfm

  output: (src) ->
    out = ''
    while src
      # escape
      if cap = @rules.escape.exec src
        # console.log 'escape', cap
        src = src[cap[0].length ..]
        out += cap[1]
        continue

      # autolink
      if cap = @rules.autolink.exec src
        # console.log 'autolink', cap
        src = src[cap[0].length ..]
        if cap[2] == '@'
          text = escape @mangle cap[1]
          href = 'mailto:' + text
        else
          text = escape cap[1]
          href = text
        out += @outputLargeBrackets { text }, { href }
        continue

      # anker
      if cap = @rules.anker.exec src
        # console.log 'anker', cap
        src = src[cap[0].length ..]
        out += @renderer.anker(cap[0][2..])
        continue

      # url (gfm)
      if !@inLink and (cap = @rules.url.exec src)
        # console.log 'url (gfm)', cap
        cap[0] = @rules._backpedal.exec(cap[0])[0]
        src = src[cap[0].length ..]
        if cap[2] == '@'
          text = escape cap[0]
          href = 'mailto:' + text
        else
          text = escape cap[0]
          if cap[1] == 'www.'
            href = 'http://' + text
          else
            href = text
        out += @outputLargeBrackets { text }, { href }
        continue

      # tag
      if cap = @rules.tag.exec src
        # console.log 'tag', cap
        if !@inLink and /^<a /i.test(cap[0])
          @inLink = true
        else if @inLink and /^<\/a>/i.test(cap[0])
          @inLink = false
        src = src[cap[0].length ..]
        out += (
          if @options.sanitize
            if @options.sanitizer
            then @options.sanitizer cap[0]
            else escape cap[0]
          else
            cap[0]
        )
        continue

      # link
      if cap = @rules.link.exec src
        # console.log 'link', cap
        src = src[cap[0].length ..]
        mark = cap[0].charAt(0)
        if mark == '!'
          text = escape cap[1]
        else
          @inLink = true
          text = @output cap[1]
          @inLink = false

        href = InlineLexer.escapes cap[2]
        title = InlineLexer.escapes cap[3]?.slice(1, -1) or ''

        out += @outputLargeBrackets { mark, text }, { href, title }
        continue

      # reflink, nolink
      if (cap = @rules.reflink.exec src) or (cap = @rules.nolink.exec src)
        # console.log 'ref|no link', cap
        src = src[cap[0].length ..]
        mark = cap[0].charAt(0)
        link = (cap[2] or cap[1]).replace(/\s+/g, ' ')
        link = @links[link.toLowerCase()]
        if !link or !link.href
          out += mark
          src = cap[0][1 .. ] + src
        else
          if mark == '!'
            text = escape cap[1]
          else
            @inLink = true
            text = @output cap[1]
            @inLink = false
          out += @outputLargeBrackets { mark, text }, link
        continue

      # note
      if cap = @rules.note.exec src
        # console.log 'note', cap
        src = src[cap[0].length ..]

        @inLink = true
        text = @output cap[1]
        @inLink = false

        @notes.push o = { text } 
        o.href = '#' + num = @notes.length
        out += @renderer.note num, text
        continue

      # br
      if cap = @rules.br.exec src
        # console.log 'br', cap
        src = src[cap[0].length ..]
        out += @renderer.br()
        continue

      # strong
      if cap = @rules.strong.exec src
        # console.log 'strong', cap
        src = src[cap[0].length ..]
        method = 
          switch cap[1]
            when '_', '*'
              'strong'
            when '~'
              # del (gfm)
              'del'
            when '='
              # Mark (markdown preview enhanced extended syntax)
              'mark'
        out += @renderer[method] @output cap[2]
        continue

      # em
      if cap = @rules.em.exec src
        # console.log 'em', cap
        src = src[cap[0].length ..]
        out += @renderer.em @output cap[6] or cap[5] or cap[4] or cap[3] or cap[2] or cap[1]
        continue

      # sup
      if cap = @rules.sup.exec src
        # console.log 'sup', cap
        src = src[cap[0].length ..]
        out += @renderer.sup @output cap[1]
        continue

      # sub
      if cap = @rules.sub.exec src
        # console.log 'sub', cap
        src = src[cap[0].length ..]
        out += @renderer.sub @output cap[1]
        continue

      # code
      if cap = @rules.code.exec src
        # console.log 'code', cap
        src = src[cap[0].length ..]
        out += @renderer.codespan escape cap[2], true
        continue

      # text
      if cap = @rules.text.exec src
        # console.log 'text', cap
        src = src[cap[0].length ..]
        out += @renderer.text escape @smartypants cap[0]
        continue

      if src
        throw new Error 'Infinite loop on byte: ' + src.charCodeAt(0)
    out

  outputLargeBrackets: ({ mark, text }, link) ->
    { href = '', title = '' } = link
    href &&= escape href
    title &&= escape title

    if @options.sanitize
      try
        prot =
          decodeURIComponent unescape href
          .replace(/[^\w:]/g, '')
          .toLowerCase()
      catch e
        return text
      if prot.indexOf('javascript:') == 0 or prot.indexOf('vbscript:') == 0 or prot.indexOf('data:') == 0
        return text

    if @options.baseUrl && ! originIndependentUrl.test(href)
      href = resolveUrl @options.baseUrl, href

    switch
      when mark == '!'
        @renderer.image href, title, text

      when /// ^$ | ^mailto: | :\/\/ | ^(\.{0,2})[\?\#\/] | ^[\w()%+:/]+$ ///ig.exec href
        href = encodeURI(href).replace /%25/g, '%'
        @renderer.link href, title, text

      else
        @renderer.ruby href, title, text

  smartypants: (text) ->
    if !@options.smartypants
      return text
    text
    .replace /---/g, '—'
    .replace /--/g, '–'
    .replace /(^|[-\u2014/(\[{"\s])'/g, '$1‘'
    .replace /'/g, '’'
    .replace /(^|[-\u2014/(\[{\u2018\s])"/g, '$1“'
    .replace /"/g, '”'
    .replace /\.{3}/g, '…'

  mangle: (text) ->
    if !@options.mangle
      return text
    out = ''
    for c, i in text
      ch = text.charCodeAt(i)
      if Math.random() > 0.5
        ch = 'x' + ch.toString(16)
      out += '&#' + ch + ';'
    out


# Renderer
class Renderer
  constructor: (@options)->

  code: (code, lang, escaped)->
    if @options.highlight
      out = @options.highlight(code, lang)
      if out? and out != code
        escaped = true
        code = out
    code =
      if escaped
      then code
      else escape code, true
    if lang
      lang = @options.langPrefix + escape(lang, true)
      """<pre><code class="#{ lang }">#{ code }</code></pre>"""
    else
      """<pre><code>#{ code }</code></pre>"""

  blockquote: (quote) ->
    """<blockquote>#{ quote }</blockquote>"""

  html: (html) ->
    html

  heading: (text, level, raw) ->
    if @options.headerIds
      id = @options.headerPrefix + raw.toLowerCase().replace(/[^\w]+/g, '-')
      """<h#{level} id="#{ id }">#{ text }</h#{level}>"""
    else
      """<h#{level}>#{ text }</h#{level}>"""

  hr: ->
    '<hr>'

  list: (body, ordered, start, taskList) ->
    type =
      if ordered
      then "ol"
      else "ul"
    classNames =
      if taskList
      then ''' class="task-list"'''
      else ''
    start_at =
      if ordered && start != 1
      then """ start="#{start}" """
      else ''
    """<#{type}#{start_at}#{classNames}>#{ body }</#{type}>"""

  listitem: (text, checked) ->
    if checked?
      attr =
        if checked
        then " checked"
        else ""
      """<li class="task-list-item"><input type="checkbox" class="task-list-item-checkbox"#{attr}>#{text}</li>"""
    else
      """<li>#{ text }</li>"""

  paragraph: (text, is_top) ->
    if is_top
      """<p>#{ text }</p>"""
    else
      "#{ text }"

  table: (header, body) ->
    """<table><thead>#{ header }</thead><tbody>#{ body }</tbody></table>"""

  tablerow: (content) ->
    """<tr>#{ content }</tr>"""

  tablecell: (content, flags) ->
    style =
      if flags.align
      then """style="text-align:#{ flags.align }" """
      else ''
    if flags.header
    then """<th #{ style }>#{ content }</th>"""
    else """<td #{ style }>#{ content }</td>"""

  # span level renderer
  strong: (text) ->
    """<strong>#{ text }</strong>"""

  mark: (text) ->
    """<abbr>#{ text }</abbr>"""

  em: (text) ->
    """<em>#{ text }</em>"""

  sup: (text) ->
    """<sup>#{ text }</sup>"""

  sub: (text) ->
    """<sub>#{ text }</sub>"""

  codespan: (text) ->
    """<code>#{ text }</code>"""

  br: ->
    '\n'

  del: (text) ->
    """<del>#{ text }</del>"""

  ruby: (ruby, title, text)->
    if title
      """<span title="#{title}"><ruby>#{text}<rp>《</rp><rt>#{ruby}</rt><rp>》</rp></ruby></span>"""
    else
      """<ruby>#{text}<rp>《</rp><rt>#{ruby}</rt><rp>》</rp></ruby>"""

  note: (num, title)->
    """<sup class="note" title="#{ title }">#{ num }</sup>"""

  link: (href, title, text) ->
    if title
    then """<a href="#{ href }" title="#{ title }">#{ text }</a>"""
    else """<a href="#{ href }">#{ text }</a>"""

  image: (href, title, text) ->
    if title
    then """<img src="#{ href }" alt="#{ text }" title="#{ title }">"""
    else """<img src="#{ href }" alt="#{ text }">"""

  anker: (code)->
    """<q cite="#{code}">--#{code}</q>"""

  text: (text) ->
    text

# returns only the textual part of the token
# no need for block level renderers
class TextRenderer
  f_nop = -> ''
  f_text = (text)-> text
  f_link = (href, title, text)-> "#{text}"
  strong: f_text
  em: f_text
  codespan: f_text
  del: f_text
  text: f_text
  note: f_text
  link: f_link
  ruby: f_link
  image: f_link
  br: f_nop

# Parsing & Compiling
class Parser
  @parse = (src, options, renderer) ->
    new Parser(options, renderer).parse src

  constructor: (@options) ->
    @tokens = []
    @token = null
    { @renderer } = @options

  parse: (src) ->
    @inline = new InlineLexer src, @options
    # use an InlineLexer with a TextRenderer to extract pure text
    @inlineText = new InlineLexer src, Object.assign {}, @options,
      renderer: new TextRenderer
    @tokens = src.reverse()
    out = ''
    while @next()
      out += @tok()
    if src.notes.length
      out += @renderer.hr()
      notes = ""
      for { text } in src.notes
        notes += @renderer.listitem text 
      out += @renderer.list notes, true, 1

    tag = @options.tag
    if tag
      out = """<#{tag}>#{out}</#{tag}>"""
    out

  next: ->
    @token = @tokens.pop()

  peek: ->
    @tokens[@tokens.length - 1] or 0

  parseText: ->
    body = @token.text
    while @peek().type == 'text'
      body += '\n' + @next().text
    @inline.output body

  ###*
  # Parse Current Token
  ###

  tok: ->
    switch @token.type
      when 'space'
        @token.text

      when 'hr'
        @renderer.hr()

      when 'heading'
        @renderer.heading(
          @inline.output(@token.text),
          @token.depth,
          unescape @inlineText.output @token.text
        )

      when 'code'
        @renderer.code(@token.text, @token.lang, @token.escaped)

      when 'table'
        cell = ''
        for o, i in @token.header
          flags =
            header: true
            align: @token.align[i]
          cell += @renderer.tablecell @inline.output(o),
            header: true
            align: @token.align[i]
        header = @renderer.tablerow(cell)

        body = ''
        for row, i in @token.cells
          cell = ''
          for _row, j in row
            cell += @renderer.tablecell @inline.output(_row),
              header: false
              align: @token.align[j]
          body += @renderer.tablerow(cell)
        @renderer.table(header, body)

      when 'blockquote_start'
        body = ''
        while @next().type != 'blockquote_end'
          body += @tok()
        @renderer.blockquote(body)

      when 'list_start'
        { ordered, start } = @token
        body = ''
        tasklist = false
        while @next().type != 'list_end'
          if @token.checked?
            taskList = true
          body += @tok()
        @renderer.list(body, ordered, start, taskList)

      when 'list_item_start'
        body = ''
        { checked } = @token
        while @next().type != 'list_item_end'
          body +=
            if @token.type == 'text'
            then @parseText()
            else @tok()
        @renderer.listitem(body, checked)

      when 'loose_item_start'
        body = ''
        { checked } = @token
        while @next().type != 'list_item_end'
          body += @tok()
        @renderer.listitem(body, checked)

      when 'html'
        html =
          if ! @token.pre
            @inline.output(@token.text)
          else
            @token.text
        @renderer.html(html)

      when 'paragraph'
        @renderer.paragraph @inline.output(@token.text), true

      when 'text'
        @renderer.paragraph @parseText(), @token.top

# Marked
marked = (src, opt) ->
  # throw error in case of non string input
  unless src
    throw new Error('marked(): input parameter is undefined or null')
  if typeof src != 'string'
    txt = Object.prototype.toString.call(src)
    throw new Error("marked(): input parameter is of type #{txt}, string expected")

  try
    opt = Object.assign({}, marked.defaults, opt)
    opt.renderer.options = opt

    tokens = Lexer.lex(src, opt)
    return Parser.parse tokens, opt
  catch e
    e.message += '\nPlease report this to https://github.com/7korobi/marked.'
    if (opt or marked.defaults).silent
      message = escape(e.message + '', true)
      return "<p>An error occured:</p><pre>#{message}</pre>"
    throw e


###
  if callback
    opt = Object.assign({}, marked.defaults, opt)
    { highlight } = opt

    try
      tokens = Lexer.lex(src, opt, links)
    catch e
      return callback(e)
    pending = tokens.length

    done = (err) ->
      if err
        opt.highlight = highlight
        return callback(err)

      try
        out = Parser.parse(tokens, opt)
      catch e
        err = e
      opt.highlight = highlight
      if err
      then callback(err)
      else callback(null, out)

    if !highlight or highlight.length < 3
      return done()

    delete opt.highlight

    if !pending
      return done()

    tokens.map (token)->
      if token.type != 'code'
        return --pending or done()
      highlight token.text, token.lang, (err, code) ->
        if err
          return done(err)
        if code in [null, token.text]
          return --pending or done()
        token.text = code
        token.escaped = true
        --pending or done()
        return
      return
    return
###

# Options
marked.options =
marked.setOptions = (opt) ->
  Object.assign marked.defaults, opt
  marked

marked.getDefaults = ->
  tag: null
  gfm: true
  tables: true
  indentCode: true
  taskLists: true
  breaks: false
  sanitize: false
  sanitizer: null
  mangle: true
  smartLists: false
  silent: false
  highlight: null
  langPrefix: 'language-'
  smartypants: false
  headerIds: true
  headerPrefix: ''
  renderer: new Renderer
  xhtml: false
  baseUrl: null
marked.defaults = marked.getDefaults()


# Expose

marked.Parser = Parser
marked.parser = Parser.parse

marked.Renderer = Renderer
marked.TextRenderer = TextRenderer

marked.Lexer = Lexer
marked.lexer = Lexer.lex

marked.InlineLexer = InlineLexer
marked.inlineLexer = InlineLexer.output

marked.parse = marked

module.exports = marked
