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
  html.replace /&(#(?:\d+)|(?:#x[0-9A-Fa-f]+)|(?:\w+));?/g, (_, n) ->
    n = n.toLowerCase()
    if n == 'colon'
      return ':'
    if n.charAt(0) == '#'
      return if n.charAt(1) == 'x' then String.fromCharCode(parseInt(n.substring(2), 16)) else String.fromCharCode(+n.substring(1))
    ''

slugo = (input)->
  input
  # Remove html tags
  .replace(/<(?:.|\n)*?>/gm, '')
  # Remove special characters
  .replace(/[!\"#$%&'\(\)\*\+,\/:;<=>\?\@\[\\\]\^`\{\|\}~]/g, '')
  # Replace dots and spaces with a separator
  .replace(/(\s|\.)/g, '-')
  # Make the whole thing lowercase
  .toLowerCase()

replace = (regex, opt) ->
  regex = regex.source
  opt = opt or ''
  self = (name, val) ->
    if !name
      return new RegExp(regex, opt)
    val = val.source or val
    val = val.replace(/(^|[^\[])\^/g, '$1')
    regex = regex.replace(name, val)
    self
  self

noop = ->
noop.exec = noop


# Block Lexer
block = 
  newline: /^\n+/
  code: /^( {4}[^\n]+\n*)+/
  fences: noop
  hr: /^( *[-*_]){3,} *(?:\n|$)/
  heading: /^ *(#{1,6}) *([^\n]+?) *#* *(?:\n|$)/
  nptable: noop
  lheading: /^([^\n]+)\n *(=|-){2,} *(?:\n|$)/
  blockquote: /^( *>[^\n]+(\n(?!def)[^\n]+)*\n*)+/
  list: /^( *)(bull)[\s\S]+?(?:hr|def|\n{2,}(?! )(?!\1bull)\n*|\s*$)/
  html: /^ *(?:comment *(?:\n|\s*$)|closed *(?:\n{2,}|\s*$)|closing *(?:\n{2,}|\s*$))/
  def: /^ *\[([^\]]+)\]: *<?([^\s>]+)>?(?: +["(]([^\n]+)[")])? *(?:\n|$)/
  table: noop
  paragraph: /^((?:[^\n]+\n?(?!hr|heading|lheading|blockquote|tag|def))+)\n*/
  text: /^[^\n]+/

block.bullet = /(?:[*+-] |\d+\.)/
block.item = /^( *)(bull)[^\n]*(?:\n(?!\1bull)[^\n]*)*/
block.item = replace(block.item, 'gm'
)( /bull/g, block.bullet
)()

block.list = replace(block.list
)( /bull/g, block.bullet
)( 'hr', '\\n+(?=\\1?(?:[-*_] *){3,}(?:\\n+|$))'
)( 'def', '\\n+(?=' + block.def.source + ')'
)()

block.blockquote = replace(block.blockquote
)( 'def', block.def
)()

block._tag = ('(?!(?:'
)+( 'a|em|strong|small|s|cite|q|dfn|abbr|data|time|code'
)+( '|var|samp|kbd|sub|sup|i|b|u|mark|ruby|rt|rp|bdi|bdo'
)+( '|span|br|wbr|ins|del|img)\\b)\\w+(?!:/|[^\\w\\s@]*@)\\b'
)

block.html = replace(block.html
)( 'comment', /<!--[\s\S]*?-->/
)( 'closed', /<(tag)[\s\S]+?<\/\1>/
)( 'closing', /<tag(?:"[^"]*"|'[^']*'|[^'">])*?>/
)( /tag/g, block._tag
)()

block.paragraph = replace(block.paragraph
)( 'hr', block.hr
)( 'heading', block.heading
)( 'lheading', block.lheading
)( 'blockquote', block.blockquote
)( 'tag', '<' + block._tag
)( 'def', block.def
)()

# Normal Block Grammar
block.normal = Object.assign {}, block

# GFM Block Grammar
block.gfm = Object.assign {}, block.normal,
  fences: /^ *(`{3,}|~{3,})[ \.]*(\S+)? *\n([\s\S]*?)\s*\1 *(\n|$)/
  paragraph: /^/
  heading: /^ *(#{1,6}) +([^\n]+?) *#* *(\n|$)/
  checkbox: /^\[([ x])\] +/

block.gfm.paragraph = replace(block.paragraph
)( '(?!', '(?!'
  + block.gfm.fences.source.replace('\\1', '\\2') + '|' 
  + block.list.source.replace('\\1', '\\3') + '|'
)()

# GFM + Tables Block Grammar

block.tables = Object.assign {}, block.gfm,
  nptable: /^ *(\S.*\|.*)\n *([-:]+ *\|[-| :]*)\n((?:.*\|.*(?:\n|$))*)\n*/
  table: /^ *\|(.+)\n *\|( *[-:]+[-| :]*)\n((?: *\|.*(?:\n|$))*)\n*/


class Lexer
  @rules: block
  @lex: (src, options) ->
    new Lexer(options).lex(src)

  constructor: (options)->
    @tokens = []
    @tokens.links = {}
    @options = options or marked.defaults
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

  token: (src, top, bq) ->
    src = src.replace(/^ +$/gm, '')
    while src
      # newline
      if cap = @rules.newline.exec src
        src = src[cap[0].length ..]
        @tokens.push
          type: 'space'
          text: cap[0]

      # code
      if cap = @rules.code.exec src
        src = src[cap[0].length ..]
        cap = cap[0].replace /^ {4}/gm, ''
        @tokens.push
          type: 'code'
          text: cap
        continue

      # fences (gfm)
      if cap = @rules.fences.exec src
        src = src[cap[0].length ..]
        @tokens.push
          type: 'code'
          lang: cap[2]
          text: cap[3] or ''
        continue

      # heading
      if cap = @rules.heading.exec src
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
          header: cap[1].replace(/^ *| *\| *$/g, '').split(/ *\| */)
          align: cap[2].replace(/^ *|\| *$/g, '').split(/ *\| */)
          cells: cap[3].replace(/\n$/, '').split('\n')
        for o, i in item.align
          item.align[i] =
            if      /^ *-+: *$/.test o  then 'right'
            else if /^ *:-+: *$/.test o then 'center'
            else if /^ *:-+ *$/.test o  then 'left'
            else                              null
        for o, i in item.cells
          item.cells[i] = o.split(/ *\| */)
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
 
      # hr
      if cap = @rules.hr.exec src
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
        src = src[cap[0].length ..]
        bull = cap[2]
        @tokens.push
          type: 'list_start'
          ordered: "." == bull.slice(-1)
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
          item = item.replace /^ *([*+-]+ |(\d+\.)+)/, ''
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
          @tokens.push type: if loose then 'loose_item_start' else 'list_item_start'
          # Recurse.
          @token item, false, bq
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
      if !bq and top and cap = @rules.def.exec src
        src = src[cap[0].length ..]
        @tokens.links[cap[1].toLowerCase()] =
          href:  cap[2]
          title: cap[3]
        continue

      # table (gfm)
      if top and cap = @rules.table.exec src
        src = src[cap[0].length ..]
        item =
          type: 'table'
          header: cap[1].replace(/^ *| *\| *$/g, '').split(/ *\| */)
          align: cap[2].replace(/^ *|\| *$/g, '').split(/ *\| */)
          cells: cap[3].replace(/(?: *\| *)?\n$/, '').split('\n')
        for o, i in item.align
          item.align[i] =
            if      /^ *-+: *$/.test(o)  then 'right'
            else if /^ *:-+: *$/.test(o) then 'center'
            else if /^ *:-+ *$/.test(o)  then 'left'
            else                               null
        for o, i in item.cells
          item.cells[i] = o
          .replace(/^ *\| *| *\| *$/g, '')
          .split(/ *\| */)

        @tokens.push item
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
        continue

      if src
        throw new Error('Infinite loop on byte: ' + src.charCodeAt(0))
    @tokens


# Inline Lexer & Compiler
inline = 
  escape: /^\\([\\`*{}\[\]()#+\-.!_>])/
  autolink: /^<([^ >]+(@|:\/)[^ >]+)>/
  url: noop
  tag: /^<!--[\s\S]*?-->|^<\/?\w+(?:"[^"]*"|'[^']*'|[^'">])*?>/
  link: /^!?\[(inside)\]\(href\)/
  reflink: /^!?\[(inside)\]\s*\[([^\]]*)\]/
  nolink: /^!?\[((?:\[[^\]]*\]|[^\[\]])*)\]/
  strong: /^__([\s\S]+?)__(?!_)|^\*\*([\s\S]+?)\*\*(?!\*)/
  em: /^\b_((?:[^_]|__)+?)_\b|^\*((?:\*\*|[\s\S])+?)\*(?!\*)/
  code: /^(`+)\s*([\s\S]*?[^`])\s*\1(?!`)/
  br: /^ {2,}\n(?!\s*$)/
  del: noop
  text: /^[\s\S]+?(?=[\\<!\[_*`]| {2,}\n|$)/
inline._inside = /(?:\[[^\]]*\]|[^\[\]]|\](?=[^\[]*\]))*/
inline._href = /\s*<?([\s\S]*?)>?(?:\s+['"]([\s\S]*?)['"])?\s*/
inline.link = replace(inline.link)('inside', inline._inside)('href', inline._href)()
inline.reflink = replace(inline.reflink)('inside', inline._inside)()

# Normal Inline Grammar
inline.normal = Object.assign({}, inline)

# GFM Inline Grammar
inline.gfm = Object.assign({}, inline.normal,
  escape: replace(inline.escape)('])', '~|])')()
  url: /^(https?:\/\/[^\s<]+[^<.,:;"')\]\s])/
  del: /^~~(?=\S)([\s\S]*?\S)~~/
  text: replace(inline.text)(']|', '~]|')('|', '|https?://|')())

# GFM + Line Breaks Inline Grammar
inline.breaks = Object.assign({}, inline.gfm,
  br: replace(inline.br)('{2,}', '*')()
  text: replace(inline.gfm.text)('{2,}', '*')(']|', '/]|')())

# Expose Inline Rules
class InlineLexer
  @rules: inline
  @output: (src, links, options) ->
    new InlineLexer(links, options).output src

  constructor: (links, options) ->
    @options = options or marked.defaults
    @links = links
    @rules = inline.normal
    @renderer = @options.renderer or new Renderer
    @renderer.options = @options
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
        src = src[cap[0].length ..]
        out += cap[1]
        continue

      # autolink
      if cap = @rules.autolink.exec src
        src = src[cap[0].length ..]
        if cap[2] == '@'
          text =
            if cap[1].charAt(6) == ':'
            then @mangle(cap[1][7..])
            else @mangle(cap[1])
          href = @mangle('mailto:') + text
        else
          text = escape(cap[1])
          href = text
        out += @renderer.link(href, null, text)
        continue

      # url (gfm)
      if !@inLink and (cap = @rules.url.exec src)
        src = src[cap[0].length ..]
        text = escape(cap[1])
        href = text
        out += @renderer.link(href, null, text)
        continue

      # tag
      if cap = @rules.tag.exec src
        if !@inLink and /^<a /i.test(cap[0])
          @inLink = true
        else if @inLink and /^<\/a>/i.test(cap[0])
          @inLink = false
        src = src[cap[0].length ..]
        out += (
          if @options.sanitize
            if @options.sanitizer 
            then @options.sanitizer(cap[0]) 
            else escape(cap[0])
          else
            cap[0]
        )
        continue

      # link
      if cap = @rules.link.exec src
        src = src[cap[0].length ..]
        @inLink = true
        out += @outputLink cap,
          href:  cap[2]
          title: cap[3]
        @inLink = false
        continue

      # reflink, nolink
      if (cap = @rules.reflink.exec src) or (cap = @rules.nolink.exec  src)
        link = (cap[2] or cap[1]).replace(/\s+/g, ' ')
        link = @links[link.toLowerCase()]
        if !link or !link.href
          src = src[1 ..]
          out += cap[0].charAt(0)
        else
          src = src[cap[0].length ..]
          @inLink = true
          out += @outputLink(cap, link)
          @inLink = false
        continue

      # strong
      if cap = @rules.strong.exec src
        src = src[cap[0].length ..]
        out += @renderer.strong @output cap[2] or cap[1]
        continue

      # em
      if cap = @rules.em.exec src
        src = src[cap[0].length ..]
        out += @renderer.em @output cap[2] or cap[1]
        continue

      # code
      if cap = @rules.code.exec src
        src = src[cap[0].length ..]
        out += @renderer.codespan escape cap[2], true
        continue

      # br
      if cap = @rules.br.exec src
        src = src[cap[0].length ..]
        out += @renderer.br()
        continue

      # del (gfm)
      if cap = @rules.del.exec src
        src = src[cap[0].length ..]
        out += @renderer.del @output cap[1]
        continue

      # text
      if cap = @rules.text.exec src
        src = src[cap[0].length ..]
        out += @renderer.text escape @smartypants cap[0]
        continue

      if src
        throw new Error 'Infinite loop on byte: ' + src.charCodeAt(0)
    out

  outputLink: (cap, link) ->
    href = escape(link.href)
    title =
      if link.title
      then escape(link.title)
      else null
    if cap[0].charAt(0) != '!'
      @renderer.link href, title, @output cap[1]
    else
      @renderer.image href, title, escape cap[1]

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
  constructor: (options) ->
    @options = options or {}

  code: (code, lang, escaped) ->
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
    id = @options.headerPrefix + slugo raw
    """<h#{level} id="#{ id }">#{ text }</h#{level}>"""

  hr: ->
    '<hr>'

  list: (body, ordered) ->
    if ordered
    then """<ol>#{ body }</ol>"""
    else """<ul>#{ body }</ul>"""

  listitem: (text) ->
    """<li>#{ text }</li>"""

  paragraph: (text) ->
    """<p>#{ text }</p>"""

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

  em: (text) ->
    """<em>#{ text }</em>"""

  codespan: (text) ->
    """<code>#{ text }</code>"""

  br: ->
    '\n'

  del: (text) ->
    """<del>#{ text }</del>"""

  link: (href, title, text) ->
    if @options.sanitize
      try
        prot =
          decodeURIComponent(unescape(href))
          .replace(/[^\w:]/g, '')
          .toLowerCase()
      catch e
        return ''
      if prot.indexOf('javascript:') == 0 or prot.indexOf('vbscript:') == 0 or prot.indexOf('data:') == 0
        return ''
    if title
    then """<a href="#{ href }" title="#{ title }">#{ text }</a>"""
    else """<a href="#{ href }">#{ text }</a>"""

  image: (href, title, text) ->
    if title
    then """<img src="#{ href }" alt="#{ text }" title="#{ title }">"""
    else """<img src="#{ href }" alt="#{ text }">"""

  text: (text) ->
    text


# Parsing & Compiling
class Parser
  @parse = (src, options, renderer) ->
    new Parser(options, renderer).parse src

  constructor: (options) ->
    @tokens = []
    @token = null
    @options = options or marked.defaults
    @options.renderer = @options.renderer or new Renderer
    @renderer = @options.renderer
    @renderer.options = @options

  parse: (src) ->
    @inline = new InlineLexer(src.links, @options, @renderer)
    @tokens = src.reverse()
    out = ''
    while @next()
      out += @tok()
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
        @renderer.heading(@inline.output(@token.text), @token.depth, @token.text)

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
        body = ''
        ordered = @token.ordered
        while @next().type != 'list_end'
          body += @tok()
        @renderer.list(body, ordered)

      when 'list_item_start'
        body = ''
        while @next().type != 'list_item_end'
          body +=
            if @token.type == 'text'
            then @parseText()
            else @tok()
        @renderer.listitem(body)

      when 'loose_item_start'
        body = ''
        while @next().type != 'list_item_end'
          body += @tok()
        @renderer.listitem(body)

      when 'html'
        html =
          if !@token.pre
          then @inline.output(@token.text)
          else @token.text
        @renderer.html(html)

      when 'paragraph'
        @renderer.paragraph(@inline.output(@token.text))

      when 'text'
        @renderer.paragraph(@parseText())



# Marked
marked = (src, opt, callback) ->
  if callback || typeof opt == 'function'
    if !callback
      callback = opt
      opt = null
    opt = Object.assign({}, marked.defaults, opt or {})
    highlight = opt.highlight

    try
      tokens = Lexer.lex(src, opt)
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

  try
    if opt
      opt = Object.assign({}, marked.defaults, opt)
    return Parser.parse Lexer.lex(src, opt), opt
  catch e
    e.message += '\nPlease report this to https://github.com/chjj/marked.'
    if (opt or marked.defaults).silent
      return '<p>An error occured:</p><pre>' + escape(e.message + '', true) + '</pre>'
    throw e
  return


# Options
marked.options =
marked.setOptions = (opt) ->
  Object.assign marked.defaults, opt
  marked

marked.defaults =
  tag: null
  gfm: true
  tables: true
  breaks: false
  sanitize: false
  sanitizer: null
  mangle: true
  smartLists: false
  silent: false
  highlight: null
  langPrefix: 'lang-'
  smartypants: false
  headerPrefix: ''
  renderer: new Renderer


# Expose

marked.Parser = Parser
marked.parser = Parser.parse

marked.Renderer = Renderer

marked.Lexer = Lexer
marked.lexer = Lexer.lex

marked.InlineLexer = InlineLexer
marked.inlineLexer = InlineLexer.output

marked.parse = marked

module.exports = marked
