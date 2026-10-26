import parsers


def test_current_layout_keeps_article_and_excludes_sidebar_and_carousel():
    html = '''<article>Our Sheikh . Official</article>
    <div class="c-layout-sidebar-menu">Navigation</div>
    <div class="c-layout-sidebar-content"><h1>Source title</h1>
    <p>Exact source text, punctuation and honorifics.</p>
    <div style="font-size:3px">External Links - References: links</div>
    <div class="c-content-title-1"><h3>Highlights</h3></div>
    <div class="row"><div class="c-content-media-2-slider">Past Events</div></div>
    </div>'''
    result = parsers.parse_article_page(html, 'https://www.naqshbandiaowaisiah.org/article.html', include_body=True)
    assert result['body_plain_text'] == 'Source title\nExact source text, punctuation and honorifics.'


def test_visible_article_references_are_retained():
    html='<main><h1>Source title</h1><div>External Links - References: original references</div><h3>Highlights</h3><p>Article prose</p></main>'
    result=parsers.parse_article_page(html,'https://www.naqshbandiaowaisiah.org/article.html',include_body=True)
    assert 'original references' in result['body_plain_text']
    assert 'Highlights' in result['body_plain_text']
