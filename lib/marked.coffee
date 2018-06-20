###
# Helpers
###

escape = (html, is_encode)->
  r_encode =
    if is_encode
    then /&/g
    else /&(?!#?\w+;)/g
  html
  .replace(r_encode, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')
  .replace(/'/g, '&#39;')

unescape = (html)->
  # explicitly match decimal, hex, and named HTML entities
  html.replace /&(#(?:\d+)|(?:#x[0-9A-Fa-f]+)|(?:\w+));?/ig, (_, n)->
    n = n.toLowerCase()
    switch
      when n == 'colon'
        ':'
      when n.charAt(0) == '#'
        String.fromCharCode(
          if n.charAt(1) == 'x'
            parseInt( n[2..], 16 )
          else
            n[1..] - 0
        )
      else
        ""

edit = (regex, opt)->
  regex = regex.source or regex
  opt = opt or ''
  self = (name, val)->
    if name
      val = val.source or val
      val = val.replace(/(^|[^\[])\^/g, '$1')
      regex = regex.replace(name, val)
      self
    else
      new RegExp(regex, opt)

resolveUrl = (base, href)->
  key = ' ' + base
  if ! baseUrls[key]
    # we can ignore everything in base after the last slash of its path component,
    # but we might need to add _that_
    # https://tools.ietf.org/html/rfc3986#section-3
    if /^[^:]+:\/*[^/]*$/.test(base)
      baseUrls[key] = base + '/'
    else
      baseUrls[key] = base.replace(/[^/]+$/, '') # rtrim not /
  base = baseUrls[key]

  switch
    when href[0..1] == '//'
      base.replace(/:[\s\S]*/, ':')
    when href.charAt(0) == '/'
      base.replace(/(:\/*[^/]*)[\s\S]*/, '$1')
    else
      base
baseUrls = {}
originIndependentUrl = /^$|^[a-z][a-z0-9+.-]*:|^[?#]/i

noop = ->
noop.exec = noop


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

###
# Block-Level Grammer
###
block =
  newline: /^ *\n+/
  code: /^( {4}[^\n]+\n*)+/
  fences: noop
  hr: /^ {0,3}((?:- *){3,}|(?:_ *){3,}|(?:\* *){3,})(?:\n|$)/
  heading: /^ *(#{1,6}) *([^\n]+?) *(?:#+ *)?(?:\n|$)/
  table: noop
  blockquote: /^( {0,3}> ?(paragraph|[^\n]*)(?:\n|$))+/
  list: /^( *)(bull)[\s\S]+?(?:hr|def|\n{2,}(?! )(?!\1bull)\n*|\s*$)/
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
  lheading: /^([^\n]+)\n *(=|-){2,} *(?:\n|$)/
  checkbox: /^\[([ xX])\] +/
  paragraph: /^([^\n]+(?:\n(?!hr|heading|lheading| {0,3}>|<\/?(?:tag)(?: +|\n|\/?>)|<(?:script|pre|style|!--))[^\n]+)*)/
  text: /^[^\n]+/
  abbr: noop

block._label = /(?!\s*\])(?:\\[\[\]]|[^\[\]])+/
block._title = /(?:"(?:\\"?|[^"\\])*"|'[^'\n]*(?:\n[^'\n]+)*\n?'|\([^()]*\))/
block.def = edit(block.def
)( 'label', block._label
)( 'title', block._title
)()

block.with_bullet = /^ *([*+-]|\d+\.) */
block.bullet = /(?:[*+-] |\d+\.)/
block.item = /^( *)(bull)[^\n]*(?:\n(?!\1bull)[^\n]*)*/
block.item = edit(block.item, 'gm'
)( /bull/g, block.bullet
)()

block.list = edit(block.list
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
block.html = edit(block.html, 'i'
)( 'comment', block._comment
)( 'tag', block._tag
)('attribute', / +[a-zA-Z:_][\w.:-]*(?: *= *"[^"\n]*"| *= *'[^'\n]*'| *= *[^\s"'=<>`]+)?/
)()

block.paragraph = edit(block.paragraph
)( 'hr', block.hr
)( 'heading', block.heading
)( 'lheading', block.lheading
)( 'tag', block._tag
)()

block.blockquote = edit(block.blockquote
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
  fences: /^ *(`{3,}|~{3,}|:{3,})[ \.]*(\S+)? *\n([\s\S]*?)\n? *\1 *(?:\n|$)/
  paragraph: /^/
  heading: /^ *(#{1,6}) +([^\n]+?) *#* *(?:\n|$)/
  abbr: /^\*\[(label)\] *\n? *: *([^\n]+?) *(?:\n|$)/

block.gfm.abbr = edit(block.gfm.abbr
)( 'label', block._label
)()

block.gfm.paragraph = edit(block.paragraph
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
  table: /^ *(.*\|.*) *\n *((\|?) *:?-+:? *(?:\| *:?-+:? *)*(\|?))(?:\n *((?:\3.*[^>\n ].*\4(?:\n|$))*)|$)/

###
# Pedantic grammar
# not support
###

class Lexer
  @rules: block
  @lex: (src, options)->
    new Lexer(options).lex(src)

  constructor: (@options)->
    @tokens = []
    @tokens.notes = []
    @tokens.links = {}
    @tokens.abbrs = {}
    @rules = block.normal
    if @options.gfm
      @rules =
        if @options.tables
        then block.tables
        else block.gfm

  lex: (src)->
    src = src
    .replace /\r\n|\r/g, '\n'
    .replace /\t/g, '    '
    .replace /\u00a0/g, ' '
    .replace /\u2424/g, '\n'
    @token src, true

  token: (src, top)->
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
        mode = cap[1][0]
        switch mode
          when ':'
            @tokens.push
              type: 'container'
              lang: cap[2]
              text: @token cap[3], top
          else
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
      if top and cap = @rules.table.exec src
        src = src[cap[0].length ..]
        trim = /^\|? *|\ *\|? *$/g

        header = splitCells cap[1].replace(trim, '')
        align = cap[2].replace(trim, '').split(/ *\| */)
        cells = cap[5]?.replace(/\n$/, '').split('\n').map((o)=> o.replace(trim, '') ) ? []

        item = { type: 'table', header, align, cells }
        for o, i in align
          align[i] =
            if      /^ *-+: *$/.test o  then 'right'
            else if /^ *:-+: *$/.test o then 'center'
            else if /^ *:-+ *$/.test o  then 'left'
            else                              null
        for o, i in item.cells
          cells[i] = splitCells o, item.align.length
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
          mode: '>'
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

      # abbr
      if cap = @rules.abbr.exec src
        # console.log 'abbr', cap
        src = src[cap[0].length ..]
        tag = cap[1]
        @tokens.abbrs[tag] ||=
          title: cap[2]
        keys =
          Object.keys @tokens.abbrs
          .join("|")
        @tokens.abbrs_reg = "(#{keys})"
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
  center: ///
    ^-(>)(
       [^\s][\s\S]*?[^\s]
      |[^\s]
    )<-(?!-)
  ///
  kbd: ///
    ^(\[)\[(
       [^\s][\s\S]*?[^\s]
      |[^\s]
    )\]\](?!\])
  ///
  strong: ///
    ^([_~*=+:\-])\1(
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
  mdi: /^:(mdi-[^:]+):(?!:)/
  code: /^(`+)\s*([\s\S]*?[^`]?)\s*\1(?!`)/
  br: /^ {2,}\n(?!\s*$)/
  del: noop,
  text: /^[\s\S]+?(?=[\\<!\[`*=+:\-]|\b_| {2,}\n|$)/
  # extended
  anker: /^\w+-\w+-\w+-\w+-\w+|-\w+-\w+-\w+|-\w+-\w+|-\w+/
  note: /^\^\[(label)\]/
  sup: /^\^((?:[^\s^]|\^\^)+?)\^(?!\^)/
  sub: /^~((?:[^\s~]|~~)+?)~(?!~)/

  _url_peice: ///
      ^$
    | ^mailto:
    | :\/\/
    | ^(\.{0,2})[\?\#\/]
    | ^[\w()%+:/]+$
  ///ig


inline._escapes = edit(inline.escape, 'g'
)('^',''
)()

inline._scheme = /[a-zA-Z][a-zA-Z0-9+.-]{1,31}/
inline._email = ///
  [a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+
  (@)
  [a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?
  (?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+
  (?![-_])
///
inline.autolink = edit(inline.autolink
)('scheme', inline._scheme
)('email', inline._email
)()

inline._attribute = /\s+[a-zA-Z:_][\w.:-]*(?:\s*=\s*"[^"]*"|\s*=\s*'[^']*'|\s*=\s*[^\s"'=<>`]+)?/
inline.tag = edit(inline.tag
)('comment', block._comment
)('attribute', inline._attribute
)()

inline._label = ///(?:
   \[[^\[\]]*\]
  |\\[\[\]]?
  |`[^`]*`
  |[^\[\]\\]
)*?///
inline._href = ///
    \s*(
       <(?:
         \\[<>]?
        |[^\s<>\\]
      )*>
      |(?:
         \\[()]?
        |\([^\s\x00-\x1f()\\]*\)
        |[^\s\x00-\x1f()\\]
      )*?
    )
  ///
inline._title = /"(?:\\"?|[^"\\])*"|'(?:\\'?|[^'\\])*'|\((?:\\\)?|[^)\\])*\)/

inline.link = edit(inline.link
)('label', inline._label
)('href', inline._href
)('title', inline._title
)()

inline.reflink = edit(inline.reflink
)('label', inline._label
)()

inline.note = edit(inline.note
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
  escape: edit(
    inline.escape
  )('])', '~|])'
  )()
  url: edit(
    /^((?:ftp|https?):\/\/|www\.)(?:[a-zA-Z0-9\-]+\.?)+[^\s<]*|^email/
  )('email', inline._email)(
  )
  _backpedal: /(?:[^?!.,:;*_~()&]+|\([^)]*\)|&(?![a-zA-Z0-9]+;$)|[?!.,:;*_~)]+(?!$))+/
  text: edit(
    inline.text
  )(']|', '~=\^\-]|'
  )('|', '|https?://|ftp://|www\\.|[a-zA-Z0-9.!#$%&\'*+/=?^_`{\\|}~-]+@|'
  )()
)

###
# GFM + Line Breaks Inline Grammar
###
inline.breaks = Object.assign({}, inline.gfm,
  br: edit(inline.br)('{2,}', '*')()
  text: edit(inline.gfm.text)('{2,}', '*')())

###
# Inline Lexer & Compiler
###
class InlineLexer
  ###
  # Expose Inline Rules
  ###
  @rules: inline
  @output: (src, options)->
    new InlineLexer(options, options).output src

  @escapes: (text)->
    text?.replace(InlineLexer.rules._escapes, '$1') or text

  constructor: ({ @notes, @links, @abbrs, @abbrs_reg }, options)->
    @options = options or marked.defaults
    @rules = inline.normal
    @renderer = @options.renderer or new Renderer
    @renderer.options = @options
    if !@notes
      throw new Error('Tokens array requires a `notes` property.')
    if !@links
      throw new Error('Tokens array requires a `links` property.')
    if ! @options.em
      @rules.em = noop
    if @options.gfm
      if @options.breaks
        @rules = inline.breaks
      else
        @rules = inline.gfm

  output: (src)->
    out = []
    while src
      # escape
      if cap = @rules.escape.exec src
        # console.log 'escape', cap
        src = src[cap[0].length ..]
        out.push cap[1]
        continue

      # autolink
      if cap = @rules.autolink.exec src
        # console.log 'autolink', cap
        src = src[cap[0].length ..]
        if cap[2] == '@'
          text = cap[1]
          href = 'mailto:' + text
        else
          text = cap[1]
          href = text
        out.push @outputLargeBrackets { text }, { href }
        continue

      ###
      # anker
      if cap = @rules.anker.exec src
        # console.log 'anker', cap
        src = src[cap[0].length ..]
        out.push @renderer.anker(cap[0])
        continue
      ###

      # url (gfm)
      if !@inLink and (cap = @rules.url.exec src)
        # console.log 'url (gfm)', cap
        cap[0] = @rules._backpedal.exec(cap[0])[0]
        src = src[cap[0].length ..]
        if cap[2] == '@'
          text = cap[0]
          href = 'mailto:' + text
        else
          text = cap[0]
          if cap[1] == 'www.'
            href = 'http://' + text
          else
            href = text
        out.push @outputLargeBrackets { text }, { href }
        continue

      # tag
      if cap = @rules.tag.exec src
        # console.log 'tag', cap
        if !@inLink and /^<a /i.test(cap[0])
          @inLink = true
        else if @inLink and /^<\/a>/i.test(cap[0])
          @inLink = false
        src = src[cap[0].length ..]
        out.push (
          if @options.sanitize
            if @options.sanitizer
            then @options.sanitizer cap[0]
            else cap[0]
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
          text = cap[1]
        else
          @inLink = true
          text = @output cap[1]
          @inLink = false

        href = InlineLexer.escapes cap[2].trim().replace /^<([\s\S]*)>$/, '$1'
        title = InlineLexer.escapes cap[3]?.slice(1, -1) or ''

        out.push @outputLargeBrackets { mark, text }, { href, title }
        continue

      # reflink, nolink
      if (cap = @rules.reflink.exec src) or (cap = @rules.nolink.exec src)
        # console.log 'ref|no link', cap
        src = src[cap[0].length ..]
        mark = cap[0].charAt(0)
        link = (cap[2] or cap[1]).replace(/\s+/g, ' ')
        link = @links[link.toLowerCase()]
        unless link?.href
          out.push mark
          src = cap[0][1 .. ] + src
          continue
        if mark == '!'
          text = cap[1]
        else
          @inLink = true
          text = @output cap[1]
          @inLink = false
        out.push @outputLargeBrackets { mark, text }, link
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
        out.push @renderer.note num, text
        continue

      # br
      if cap = @rules.br.exec src
        # console.log 'br', cap
        src = src[cap[0].length ..]
        out.push @renderer.br()
        continue

      # kbd, strong
      if (cap = @rules.kbd.exec src) or (cap = @rules.center.exec src) or (cap = @rules.strong.exec src)
        # console.log 'strong', cap
        src = src[cap[0].length ..]
        method = 
          switch cap[1]
            when '_', '*'
              'strong'
            when '>'
              # center (markdown-it)
              'center'
            when '-'
              # strikeout (markdown-it)
              'strikeout'
            when ':'
              # span (markdown-it)
              'span'
            when '+'
              # ins (markdown-it)
              'ins'
            when '['
              # kbd (markdown-it)
              'kbd'
            when '~'
              # del (gfm)
              'del'
            when '='
              # Mark (markdown preview enhanced extended syntax)
              'mark'
        out.push @renderer[method] @output cap[2]
        continue

      # em
      if cap = @rules.em.exec src
        # console.log 'em', cap
        src = src[cap[0].length ..]
        out.push @renderer.em @output cap[6] or cap[5] or cap[4] or cap[3] or cap[2] or cap[1], cap[0][0]
        continue

      # sup
      if cap = @rules.sup.exec src
        # console.log 'sup', cap
        src = src[cap[0].length ..]
        out.push @renderer.sup @output cap[1]
        continue

      # sub
      if cap = @rules.sub.exec src
        # console.log 'sub', cap
        src = src[cap[0].length ..]
        out.push @renderer.sub @output cap[1]
        continue

      # code
      if cap = @rules.code.exec src
        # console.log 'code', cap
        src = src[cap[0].length ..]
        out.push @renderer.codespan cap[2], true
        continue

      # mdi
      if cap = @rules.mdi.exec src
        # console.log 'mdi', cap
        src = src[cap[0].length ..]
        out.push @renderer.mdi cap[1]
        continue

      # text
      if cap = @rules.text.exec src
        # console.log 'text', cap
        src = src[cap[0].length ..]
        text = @smartypants cap[0]
        if @abbrs_reg
          for s in text.split @abbrs_reg
            o = @links[s]
            if o
              out.push @renderer.abbr s, o.title
            else
              out.push @renderer.text s
        else
          out.push @renderer.text text
        continue

      if src
        throw new Error 'Infinite loop on byte: ' + src.charCodeAt(0)
    out

  outputLargeBrackets: ({ mark, text }, { href = '', title = '' })->
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
      base = resolveUrl @options.baseUrl, href
    url = @renderer.url href, base
    switch mark
      when '!'
        @renderer.image url, title, text
      else
        @renderer.link url, title, text

  smartypants: (text)->
    if !@options.smartypants
      return text
    text
    # markdown-it replacements
    .replace /\+\-/g, '\u00B1'
    # markdown-it replacements
    .replace /\+\-/g, '\u00B1'
    # em-dashes
    .replace /---/g, '\u2014'
    # en-dashes
    .replace /--/g, '\u2013'
    # opening singles
    .replace /(^|[-\u2014/(\[{"\s])'/g, '$1\u2018'
    # closing singles & apostrophes
    .replace /'/g, '\u2019'
    # opening doubles
    .replace /(^|[-\u2014/(\[{\u2018\s])"/g, '$1\u201c'
    # closing doubles
    .replace /"/g, '\u201d'
    # ellipses
    .replace /\.{3}/g, '\u2026'


# Renderer
class Renderer
  constructor: (@options)->

  container: (text, lang)->
    text = text.join("") if text?.join
    """<div class="#{ lang }">#{ text }</div>"""

  code: (code, lang, escaped)->
    if @options.highlight
      out = @options.highlight(code, lang)
      if out? and out != code
        escaped = true
        code = out
    unless escaped
      code = escape code
    if lang
      lang = @options.langPrefix + escape(lang, true)
      """<pre><code class="#{ lang }">#{ code }</code></pre>"""
    else
      """<pre><code>#{ code }</code></pre>"""

  blockquote: (quote)->
    quote = quote.join("")
    """<blockquote>#{ quote }</blockquote>"""

  html: (html)->
    html = html.join("") if html?.join
    html

  heading: (text, level, raw)->
    text = text.join("") if text?.join
    if @options.headerIds
      id = @options.headerPrefix + raw.toLowerCase().replace(/[^\w]+/g, '-')
      """<h#{level} id="#{ id }">#{ text }</h#{level}>"""
    else
      """<h#{level}>#{ text }</h#{level}>"""

  hr: ->
    '<hr />'

  list: (body, ordered, start, taskList)->
    body = body.join("")
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

  listitem: (text, checked)->
    text = text.join("") if text?.join
    if checked?
      attr =
        if checked
        then " checked=\"\" disabled=\"\""
        else " disabled=\"\""
      """<li><input#{attr} type="checkbox">#{text}</li>"""
    else
      """<li>#{ text }</li>"""

  paragraph: (text, is_top)->
    text = text.join("") if text?.join
    """<p>#{ text }</p>"""

  table: (header, body)->
    body = body.join("")
    """<table><thead>#{ header }</thead><tbody>#{ body }</tbody></table>"""

  tablerow: (content)->
    content = content.join("")
    """<tr>#{ content }</tr>"""

  tablecell: (content, flags)->
    content = content.join("")
    style =
      if flags.align
      then " align=\"#{ flags.align }\" "
      else ''
    if flags.header
    then """<th#{ style }>#{ content }</th>"""
    else """<td#{ style }>#{ content }</td>"""

  # span level renderer
  strong: (text)->
    text = text.join("") if text?.join
    """<strong>#{ text }</strong>"""

  mdi: (name)->
    """<i class="mdi #{name}"></i>"""

  center: (text)->
    text = text.join("") if text?.join
    """<center>#{ text }</center>"""

  strikeout: (text)->
    text = text.join("") if text?.join
    """<s>#{ text }</s>"""

  span: (text)->
    text = text.join("") if text?.join
    """<span>#{ text }</span>"""

  ins: (text)->
    text = text.join("") if text?.join
    """<ins>#{ text }</ins>"""

  kbd: (text)->
    text = text.join("") if text?.join
    """<kbd>#{ text }</kbd>"""

  abbr: (text, title)->
    text = text.join("") if text?.join
    """<abbr title="#{title}">#{ text }</abbr>"""

  mark: (text)->
    text = text.join("") if text?.join
    """<mark>#{ text }</mark>"""

  em: (text)->
    text = text.join("") if text?.join
    """<em>#{ text }</em>"""

  sup: (text)->
    text = text.join("") if text?.join
    """<sup>#{ text }</sup>"""

  sub: (text)->
    text = text.join("") if text?.join
    """<sub>#{ text }</sub>"""

  codespan: (text)->
    text = text.join("") if text?.join
    text = escape text
    """<code>#{ text }</code>"""

  br: ->
    '<br />'

  del: (text)->
    text = text.join("") if text?.join
    """<del>#{ text }</del>"""

  note: (num, title)->
    text = text.join("") if text?.join
    """<sup class="note" title="#{ title }">#{ num }</sup>"""

  link: (href, title, text)->
    href = encodeURI href
    text = text.join("") if text?.join
    if title
      title = escape title
      """<a href="#{ href }" title="#{ title }">#{ text }</a>"""
    else
      """<a href="#{ href }">#{ text }</a>"""

  image: (href, title, text)->
    href = encodeURI href
    text = text.join("") if text?.join
    if title
      title = escape title
      """<img src="#{ href }" alt="#{ text }" title="#{ title }">"""
    else
      """<img src="#{ href }" alt="#{ text }">"""

  text: (text)->
    text = escape text
    text

  url: (href, base = "")->
    decodeURIComponent "#{base}#{href}"

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
  url: f_nop

# Parsing & Compiling
class Parser
  @parse = (src, options, renderer)->
    new Parser(options, renderer).parse src

  constructor: (@options)->
    @tokens = []
    @token = null
    { @renderer } = @options

  parse: (src)->
    { m } = @options
    @inline = new InlineLexer src, @options
    # use an InlineLexer with a TextRenderer to extract pure text
    @inlineText = new InlineLexer src, Object.assign {}, @options,
      renderer: new TextRenderer
    @tokens = src.reverse()
    out = []
    while @next()
      out.push @tok()
    if src.notes.length
      out.push @renderer.hr()
      notes = []
      for { text } in src.notes
        notes.push @renderer.listitem text 
      out.push @renderer.list notes, true, 1

    tag = @options.tag
    if tag
      m tag, {}, out
    else
      out.join("")

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
          @inlineText.output(@token.text).join("")
        )

      when 'container'
        @renderer.container(@token.text, @token.lang)

      when 'code'
        @renderer.code(@token.text, @token.lang, @token.escaped)

      when 'table'
        cell = []
        for o, i in @token.header
          flags =
            header: true
            align: @token.align[i]
          cell.push @renderer.tablecell @inline.output(o),
            header: true
            align: @token.align[i]
        header = @renderer.tablerow(cell)

        body = []
        for row, i in @token.cells
          cell = []
          for _row, j in row
            cell.push @renderer.tablecell @inline.output(_row),
              header: false
              align: @token.align[j]
          body.push @renderer.tablerow(cell)
        @renderer.table(header, body)

      when 'blockquote_start'
        { mode } = @token
        body = []
        while @next().type != 'blockquote_end'
          body.push @tok()
        @renderer.blockquote(body, mode)

      when 'list_start'
        { ordered, start } = @token
        body = []
        tasklist = false
        while @next().type != 'list_end'
          if @token.checked?
            taskList = true
          body.push @tok()
        @renderer.list(body, ordered, start, taskList)

      when 'list_item_start'
        body = []
        { checked } = @token
        while @next().type != 'list_item_end'
          if @token.type == 'text'
          then body = [ ...body, ...@parseText() ]
          else body.push @tok()
        @renderer.listitem(body, checked)

      when 'loose_item_start'
        body = []
        { checked } = @token
        while @next().type != 'list_item_end'
          body.push @tok()
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
marked = (src, opt)->
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
    { m } = opt
    e.message += '\nPlease report this to https://github.com/7korobi/marked.'
    if (opt or marked.defaults).silent
      message = "#{e.message}"
      return m 'p', {}, [
        "An error occured:",
        m 'pre', {}, message
      ]
    throw e


# Options
marked.options =
marked.setOptions = (opt)->
  Object.assign marked.defaults, opt
  marked

marked.getDefaults = ->
  m = (tag, { attrs }, children)->
    attrs =
      for key, val of attrs
        " #{key}=\"#{val}\""
    "<#{tag}#{attrs.join('')}>#{children.join('')}</#{tag}>"

  baseUrl: null
  breaks: false
  gfm: true
  headerIds: true
  headerPrefix: ''
  highlight: null
  langPrefix: 'language-'
  mangle: true
  pedantic: false
  renderer: new Renderer
  sanitize: false
  sanitizer: null
  silent: false
  smartLists: false
  smartypants: false
  tables: true
  xhtml: false

  em: true
  indentCode: true
  taskLists: true
  tag: null
  m: m

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
