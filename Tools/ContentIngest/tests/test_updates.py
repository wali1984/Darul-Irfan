import schema
import updates

HTML = '''<article>Sidebar</article><div class="c-layout-sidebar-content">
<h1>Exact title<span class="by-author">Exact honorific</span></h1>
<h1 class="hidden-lg hidden-md">Exact title</h1>
<div><span class="icon-calendar"></span><span>06-09-2026</span></div>
<div><span class="icon-pointer"></span><span>Exact venue</span></div>
<h2 class="listing-urdu-heading">اصل عنوان</h2>
<div class="margin-top-25">اصل عبارت۔<br>Next source line.</div>
<div class="margin-top-25" style="font-size: 3px;color:white">Hidden search keywords</div>
<img src="/uploads/4283/1.JPG"><img src="https://unrelated.example/advert.jpg">
</div>'''

def test_notice_preserves_source_fields_without_duplicate_heading_or_hidden_keywords():
    group,item=updates.parse_update(HTML,'https://www.naqshbandiaowaisiah.org/press-release/4283/source.html','permissionConfirmed',True)
    assert group == 'articles'
    assert item['title'] == 'Exact title'
    assert item['author'] == 'Exact honorific'
    assert item['bodyPlainText'] == 'اصل عبارت۔\nNext source line.'
    assert item['mediaUrls'] == ['https://www.naqshbandiaowaisiah.org/uploads/4283/1.JPG']
    assert not schema.validate_content_item(item)

def test_event_has_source_venue_and_does_not_claim_an_exact_start_time():
    group,item=updates.parse_update(HTML,'https://www.naqshbandiaowaisiah.org/seminar/4283/source.html','permissionConfirmed',True)
    assert group == 'events'
    assert item['startDate'] == '2026-09-06T00:00:00Z'
    assert item['datesAreApproximate'] is True
    assert item['venue'] == 'Exact venue'
    assert not schema.validate_community_event(item)

def test_link_only_mode_does_not_include_source_prose():
    _,item=updates.parse_update(HTML,'https://www.naqshbandiaowaisiah.org/announcement/4283/source.html','linkOnly',False)
    assert 'bodyPlainText' not in item

def test_listing_never_follows_an_external_host_or_wrong_section():
    html='<a href="/press-release/1/source.html">one</a><a href="https://evil.example/press-release/2/source.html">two</a><a href="/seminar/3/source.html">three</a>'
    assert updates.detail_links(html,'https://www.naqshbandiaowaisiah.org/press-releases','press-release') == ['https://www.naqshbandiaowaisiah.org/press-release/1/source.html']
