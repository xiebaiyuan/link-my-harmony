import type common from '@ohos.app.ability.common';
import { emptyLinkItem, type LinkItem, type CollectionItem, type LinkTag } from '../common/Models';
import { LinkwardenApi } from '../services/LinkwardenApi';
import type { DashboardTotals } from '../services/LinkwardenApi';
import { normalizeInstanceUrl } from '../common/Query';
import {
  createDefaultSessionState,
  normalizeThemeMode,
  type ThemeMode,
} from '../common/SessionState';
import { createQuickMenuActions, createThemeOptions, createThemePalette, shouldReturnToDashboard, type MainView, type QuickMenuAction, type ThemeOption } from '../common/UiDesign';
import { SessionStorage } from '../services/SessionStorage';
import { consumePendingSharedIntent } from '../common/ShareIntent';

type ElementsView = 'links' | 'collections' | 'tags';
type ActiveModal = 'none' | 'add' | 'edit' | 'collection' | 'collection-picker';
type CollectionFormSource = 'add' | 'edit';

interface ParsedLinkInput {
  url: string;
  title: string;
}

interface CollectionPreviewSection {
  collection: CollectionItem;
  links: Array<LinkItem>;
}

@Entry
@Component
struct Index {
  @State instance: string = 'https://link.xiebaiyuan.com:45456';
  @State username: string = '';
  @State password: string = '';
  @State token: string = '';
  @State currentUserId: number = 0;
  @State themeMode: ThemeMode = 'system';

  @State searchQuery: string = '';
  @State newLinkUrl: string = '';
  @State newLinkTitle: string = '';
  @State newLinkTitleEdited: boolean = false;
  @State newLinkCollectionQuery: string = '';
  @State newLinkTagsInput: string = '';
  @State newTagPickerQuery: string = '';
  @State mainView: MainView = 'dashboard';
  @State elementsView: ElementsView = 'links';
  @State selectedCollectionFilterId: number = 0;
  @State showPinnedOnly: boolean = false;
  @State searchPageQuery: string = '';
  @State collectionSearchQuery: string = '';
  @State tagSearchQuery: string = '';
  @State searchShowAllLinks: boolean = false;
  @State searchShowAllCollections: boolean = false;
  @State searchShowAllTags: boolean = false;

  @State links: Array<LinkItem> = [];
  @State dashboardLinks: Array<LinkItem> = [];
  @State pinnedLinks: Array<LinkItem> = [];
  @State homePreviewLinks: Array<LinkItem> = [];
  @State collections: Array<CollectionItem> = [];
  @State knownTagNames: Array<string> = [];
  @State allTags: Array<LinkTag> = [];
  @State pinnedTotal: number = -1;
  @State tagsTotal: number = -1;
  @State linksTotal: number = -1;
  @State nextCursor: number = 0;
  @State hasMore: boolean = true;

  @State loading: boolean = false;
  @State dashboardLoading: boolean = false;
  @State dashboardRefreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State restoring: boolean = true;
  @State notice: string = '';
  @State noticeIsError: boolean = false;

  @State settingsInstance: string = 'https://link.xiebaiyuan.com:45456';

  @State selectedLink: LinkItem = emptyLinkItem();
  @State detailLoading: boolean = false;
  @State detailSaving: boolean = false;
  @State detailDeleting: boolean = false;
  @State highlightedLinkId: number = 0;

  @State editName: string = '';
  @State editUrl: string = '';
  @State editDescription: string = '';
  @State editPinned: boolean = false;
  @State editCollectionQuery: string = '';
  @State editTagsInput: string = '';
  @State editTagPickerQuery: string = '';
  @State activeModal: ActiveModal = 'none';
  @State collectionModalReturn: ActiveModal = 'add';
  @State collectionModalSource: CollectionFormSource = 'add';
  @State collectionPickerSource: CollectionFormSource = 'add';
  @State collectionPickerQuery: string = '';
  @State newCollectionName: string = '';
  @State newCollectionDescription: string = '';
  @State newCollectionColor: string = '#2563eb';
  @State newCollectionParentQuery: string = '';
  @State collectionSaving: boolean = false;
  @State pinSaving: boolean = false;
  @State quickMenuOpen: boolean = false;
  @StorageLink('safeAreaTop') safeAreaTop: number = 44;
  @StorageLink('deviceDarkMode') deviceDarkMode: boolean = false;

  private api: LinkwardenApi = new LinkwardenApi('https://link.xiebaiyuan.com:45456', '');
  private storage: SessionStorage | null = null;
  private hasRestoredSession: boolean = false;
  private sharePollTimer: number = -1;
  private noticeTimer: number = -1;

  aboutToAppear(): void {
    console.info('Index aboutToAppear');
    if (this.hasRestoredSession) {
      this.startSharePolling();
      return;
    }

    this.hasRestoredSession = true;
    this.startSharePolling();
    this.storage = new SessionStorage(getContext(this));
    this.restoreSession();
  }

  aboutToDisappear(): void {
    if (this.sharePollTimer >= 0) {
      clearInterval(this.sharePollTimer);
      this.sharePollTimer = -1;
      console.info('Index share poll stopped');
    }

    if (this.noticeTimer >= 0) {
      clearTimeout(this.noticeTimer);
      this.noticeTimer = -1;
    }
  }

  onPageShow(): void {
    console.info(`Index onPageShow restoring=${this.restoring}`);
    if (this.restoring) {
      return;
    }

    this.consumeSharedUrlAndMaybeSave().catch((error: Object) => {
      this.setNotice(`Share handling failed: ${this.formatError(error)}`, true);
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (this.restoring) {
          Column({ space: 12 }) {
            Text('Restoring session...')
              .fontSize(14)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start);
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: 12, right: 12, top: 20, bottom: 24 });
        } else if (this.token.length === 0) {
          Scroll() {
            Column({ space: 12 }) {
              this.LoginPanel();
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 20, bottom: 24 });
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ top: this.safeAreaTop })
          .scrollBar(BarState.Off);
        } else {
          this.MainPanel();
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.pageColor());

      if (!this.restoring && this.token.length > 0) {
        Column() {
          Column({ space: 6 }) {
            if (this.mainView === 'dashboard') {
              if (this.quickMenuOpen) {
                this.QuickMenuDropdown();
              }
              this.QuickMenuButton();
            } else {
              this.HomeButton();
            }
          }
          .alignItems(HorizontalAlign.End);
        }
        .width('100%')
        .alignItems(HorizontalAlign.End)
        .padding({ bottom: 100, right: 20 })
        .hitTestBehavior(HitTestMode.Transparent)
        .zIndex(100);
      }

      if (this.notice.length > 0) {
        Column() {
          this.NoticeToast();
        }
        .margin({ bottom: 20 })
        .align(Alignment.Bottom);
      }

      if (this.activeModal === 'add') {
        this.AddLinkOverlay();
      }

      if (this.activeModal === 'edit') {
        this.EditLinkOverlay();
      }

      if (this.activeModal === 'collection') {
        this.CollectionOverlay();
      }

      if (this.activeModal === 'collection-picker') {
        this.CollectionPickerOverlay();
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageColor());
  }

  @Builder
  private LoginPanel() {
    Column({ space: 10 }) {
      this.SectionSubtitle('Sign in to manage links, collections, and quick capture.');

      TextInput({ placeholder: 'Server URL', text: this.instance })
        .onChange((value: string) => {
          this.instance = value;
        })
        .backgroundColor(this.inputBackgroundColor())
        .fontColor(this.primaryTextColor())
        .borderRadius(12)
        .width('100%');

      TextInput({ placeholder: 'Username', text: this.username })
        .onChange((value: string) => {
          this.username = value;
        })
        .backgroundColor(this.inputBackgroundColor())
        .fontColor(this.primaryTextColor())
        .borderRadius(12)
        .width('100%');

      TextInput({ placeholder: 'Password', text: this.password })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.password = value;
        })
        .backgroundColor(this.inputBackgroundColor())
        .fontColor(this.primaryTextColor())
        .borderRadius(12)
        .width('100%');

      this.ThemePicker();

      Button(this.loading ? 'Signing in...' : 'Sign In')
        .enabled(!this.loading)
        .width('100%')
        .onClick(() => {
          this.handleSignIn();
        });
    }
    .padding(12)
    .backgroundColor(this.cardColor())
    .borderRadius(12)
    .width('100%');
  }

  @Builder
  private MainPanel() {
    Column({ space: 0 }) {
      Row() {
        Column({ space: 2 }) {
          Text(this.mainViewTitle())
            .fontSize(this.mainView === 'dashboard' ? 24 : 20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          Text(this.mainViewSubtitle())
            .fontSize(12)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ right: this.mainView === 'dashboard' ? 60 : 90 });
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 });

      if (this.mainView === 'dashboard') {
        Column() {
          Refresh({ refreshing: $$this.dashboardRefreshing }) {
            Scroll() {
              Column({ space: 10 }) {
                this.DashboardPanel();
              }
              .padding({ left: 12, right: 12, top: 12, bottom: 24 })
              .width('100%');
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off);
          }
          .layoutWeight(1)
          .width('100%')
          .onStateChange((state: RefreshStatus) => {
            if (state === RefreshStatus.Refresh) {
              this.handleDashboardPullRefresh();
            }
          });
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(this.surfaceColor())
        .borderRadius(18);
      } else {
        Column() {
          if (this.mainView === 'elements') {
            this.ElementsPanel();
          } else if (this.mainView === 'search') {
            this.SearchPanel();
          } else {
            this.SettingsPanel();
          }
        }
        .layoutWeight(1)
        .padding(12)
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(this.surfaceColor())
        .borderRadius(18);
      }
    }
    .padding({ left: 12, right: 12, top: this.safeAreaTop + 12, bottom: 12 })
    .width('100%')
    .height('100%');
  }


  @Builder
  private QuickMenuButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.ellipsis_circle'))
        .fontSize(24)
        .fontColor([this.accentColor()]);
    }
    .type(ButtonType.Normal)
    .width(48)
    .height(48)
    .padding(0)
    .backgroundColor(this.fabBackgroundColor())
    .border({ width: 1, color: this.fabBorderColor() })
    .borderRadius(999)
    .shadow({ radius: 12, color: this.floatingDockShadowColor(), offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.quickMenuOpen = !this.quickMenuOpen;
    });
  }

  @Builder
  private HomeButton() {
    Button() {
      SymbolGlyph($r('sys.symbol.house_fill'))
        .fontSize(22)
        .fontColor([this.accentColor()]);
    }
    .type(ButtonType.Normal)
    .width(48)
    .height(48)
    .padding(0)
    .backgroundColor(this.fabBackgroundColor())
    .border({ width: 1, color: this.fabBorderColor() })
    .borderRadius(999)
    .shadow({ radius: 12, color: this.floatingDockShadowColor(), offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.quickMenuOpen = false;
      this.mainView = 'dashboard';
      this.refreshDashboard();
    });
  }

  @Builder
  private QuickMenuDropdown() {
    Column({ space: 6 }) {
      ForEach(createQuickMenuActions(), (action: QuickMenuAction) => {
        this.QuickMenuItem(action);
      }, (action: QuickMenuAction) => action.id);
    }
    .width(168)
    .padding(8)
    .backgroundColor(this.cardColor())
    .border({ width: 1, color: this.panelBorderColor() })
    .borderRadius(18)
    .shadow({ radius: 18, color: this.floatingDockShadowColor(), offsetX: 0, offsetY: 10 });
  }

  @Builder
  private QuickMenuItem(action: QuickMenuAction) {
    Button() {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.' + action.symbolKey))
          .fontSize(18)
          .fontColor([this.accentColor()])
          .width(22)
          .height(22);

        Text(action.label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Color.Transparent)
    .borderRadius(12)
    .onClick(() => {
      this.handleQuickMenuAction(action.id);
    });
  }

  @Builder
  private NoticeToast() {
    Row() {
      Text(this.notice)
        .fontSize(13)
        .fontColor('#ffffff')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start);
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.noticeIsError ? '#D14343' : '#1F7A5A')
    .borderRadius(14)
    .shadow({ radius: 12, color: '#33000000', offsetX: 0, offsetY: 6 })
    .constraintSize({ maxWidth: '78%' })
    .margin({ bottom: 28 });
  }

  @Builder
  private ElementsPanel() {
    Column({ space: 12 }) {
      // Segmented control
      Row() {
        Text('Links')
          .layoutWeight(1)
          .height(32)
          .fontSize(13)
          .fontWeight(this.elementsView === 'links' ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.elementsView === 'links' ? this.tabActiveTextColor() : this.secondaryTextColor())
          .textAlign(TextAlign.Center)
          .backgroundColor(this.elementsView === 'links' ? this.tabActiveColor() : Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.elementsView = 'links';
            this.refreshLinks(true);
          });

        Text('Collections')
          .layoutWeight(1)
          .height(32)
          .fontSize(13)
          .fontWeight(this.elementsView === 'collections' ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.elementsView === 'collections' ? this.tabActiveTextColor() : this.secondaryTextColor())
          .textAlign(TextAlign.Center)
          .backgroundColor(this.elementsView === 'collections' ? this.tabActiveColor() : Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.elementsView = 'collections';
            this.refreshDashboard();
          });

        Text('Tags')
          .layoutWeight(1)
          .height(32)
          .fontSize(13)
          .fontWeight(this.elementsView === 'tags' ? FontWeight.Bold : FontWeight.Regular)
          .fontColor(this.elementsView === 'tags' ? this.tabActiveTextColor() : this.secondaryTextColor())
          .textAlign(TextAlign.Center)
          .backgroundColor(this.elementsView === 'tags' ? this.tabActiveColor() : Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.elementsView = 'tags';
          });
      }
      .width('100%')
      .padding(4)
      .backgroundColor(this.inputBackgroundColor())
      .borderRadius(12);

      if (this.elementsView === 'links') {
        Column() {
          this.LinksPanel();
        }
        .layoutWeight(1)
        .width('100%');
      } else if (this.elementsView === 'collections') {
        Column() {
          this.CollectionsPanel();
        }
        .layoutWeight(1)
        .width('100%');
      } else {
        Column() {
          this.TagsPanel();
        }
        .layoutWeight(1)
        .width('100%');
      }
    }
    .height('100%')
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private LinksPanel() {
    Column({ space: 10 }) {
      // Header row: count + add button
      Row({ space: 8 }) {
        Text(`${this.links.length} links`)
          .fontSize(12)
          .fontColor(this.secondaryTextColor())
          .layoutWeight(1)
          .textAlign(TextAlign.Start);

        this.InlineActionButton('＋', () => {
          this.openAddModal();
        });
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center);

      // Filter chip + search
      Row({ space: 8 }) {
        Text(this.showPinnedOnly ? '📌 Pinned' : '≡ All')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.showPinnedOnly ? this.tabActiveTextColor() : this.secondaryTextColor())
          .padding({ left: 12, right: 12 })
          .height(36)
          .backgroundColor(this.showPinnedOnly ? this.tabActiveColor() : this.inputBackgroundColor())
          .borderRadius(999)
          .onClick(() => {
            this.selectedCollectionFilterId = 0;
            this.showPinnedOnly = !this.showPinnedOnly;
            this.refreshLinks(true);
          });

        TextInput({ placeholder: '🔍  Search links', text: this.searchQuery })
          .onChange((value: string) => {
            this.searchQuery = value;
            this.refreshLinks(true);
          })
          .backgroundColor(this.inputBackgroundColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(12)
          .height(36)
          .layoutWeight(1);
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.selectedCollectionFilterId > 0) {
        Row({ space: 6 }) {
          Text('🗂')
            .fontSize(12);
          Text(this.activeCollectionName())
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.tabActiveTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
          Text('✕')
            .fontSize(12)
            .fontColor(this.tabActiveTextColor())
            .onClick(() => {
              this.selectedCollectionFilterId = 0;
              this.refreshLinks(true);
            });
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .height(32)
        .backgroundColor(this.tabActiveColor())
        .borderRadius(999)
        .alignItems(VerticalAlign.Center);
      }

      if (this.links.length === 0) {
        Text(this.loading ? 'Loading links…' : 'No links yet.')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 24, bottom: 8 });
      }

      List({ space: 8 }) {
        ForEach(this.links, (item: LinkItem) => {
          ListItem() {
            this.LinkCard(item);
          };
        }, (item: LinkItem) => `${item.id}-${item.url}`)
      }
      .divider({ strokeWidth: 0 })
      .layoutWeight(1)
      .width('100%');

      if (this.hasMore) {
        Text(this.loadingMore ? 'Loading more…' : 'Load more')
          .enabled(!this.loadingMore)
          .fontSize(13)
          .fontColor(this.accentColor())
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            this.refreshLinks(false);
          });
      }
    }
    .height('100%')
    .width('100%');
  }

  @Builder
  private CollectionsPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        this.SectionSubtitle(`${this.filteredCollections().length} collections`);
      }
      .width('100%');

      TextInput({ placeholder: 'Search collections', text: this.collectionSearchQuery })
        .onChange((value: string) => {
          this.collectionSearchQuery = value;
        })
        .backgroundColor(this.inputBackgroundColor())
        .fontColor(this.primaryTextColor())
        .borderRadius(12)
        .width('100%');

      if (this.filteredCollections().length === 0) {
        Text(this.collections.length === 0 ? 'No collections.' : 'No collections match this search.')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ top: 8, bottom: 8 });
      }

      List({ space: 8 }) {
        ForEach(this.filteredCollections(), (collection: CollectionItem) => {
          ListItem() {
            this.CollectionRow(collection);
          };
        }, (collection: CollectionItem) => `collection-panel-${collection.id}`)
      }
      .divider({ strokeWidth: 0 })
      .layoutWeight(1)
      .width('100%');
    }
    .height('100%')
    .width('100%');
  }

  @Builder
  private TagsPanel() {
    Scroll() {
      Column({ space: 8 }) {
        this.SectionSubtitle(`${this.filteredTags().length} tags`);

        TextInput({ placeholder: 'Search tags', text: this.tagSearchQuery })
          .onChange((value: string) => {
            this.tagSearchQuery = value;
          })
          .backgroundColor(this.inputBackgroundColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(12)
          .width('100%');

        if (this.filteredTags().length === 0) {
          Text('No tags found.')
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ top: 8, bottom: 8 });
        } else {
          ForEach(this.filteredTags(), (tag: string) => {
            this.TagListRow(tag);
          }, (tag: string) => `tag-${tag}`);
        }
      }
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ bottom: 96 });
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off);
  }

  @Builder
  private SearchPanel() {
    Scroll() {
      Column({ space: 10 }) {
        this.SectionTitle('Search');

        Row({ space: 8 }) {
          TextInput({ placeholder: 'Search links, collections, tags', text: this.searchPageQuery })
            .onChange((value: string) => {
              this.searchPageQuery = value;
              this.searchShowAllLinks = false;
              this.searchShowAllCollections = false;
              this.searchShowAllTags = false;
            })
            .backgroundColor(this.inputBackgroundColor())
            .fontColor(this.primaryTextColor())
            .borderRadius(12)
            .layoutWeight(1);

          Button('Search')
            .height(44)
            .backgroundColor(this.secondaryActionBackgroundColor())
            .fontColor(this.secondaryActionTextColor())
            .borderRadius(12)
            .border({ width: 1, color: this.accentColor() })
            .onClick(() => {
              this.refreshLinks(true);
              this.refreshDashboard();
            });
        }
        .width('100%');

        if (this.searchPageQuery.trim().length === 0) {
          Text('Insert a search term to search links, collections and tags.')
            .fontSize(13)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ top: 8, bottom: 8 });
        } else {
          if (!this.searchHasAnyResult()) {
            Text('No results found for this search term.')
              .fontSize(13)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding({ top: 8, bottom: 8 });
          }

          this.SearchGroup('Links', this.filteredLinksForSearch().length);
          ForEach(this.filteredLinksForSearch().slice(0, this.searchShowAllLinks ? this.filteredLinksForSearch().length : 5), (item: LinkItem) => {
            this.LinkCard(item);
          }, (item: LinkItem) => `search-link-${item.id}`);
          if (this.filteredLinksForSearch().length > 5) {
            Button(this.searchShowAllLinks ? 'Show Less' : 'Show More')
              .fontColor(this.accentColor())
              .backgroundColor(this.cardColor())
              .borderRadius(10)
              .onClick(() => {
                this.searchShowAllLinks = !this.searchShowAllLinks;
              });
          }

          this.SearchGroup('Collections', this.filteredCollectionsForSearch().length);
          ForEach(this.filteredCollectionsForSearch().slice(0, this.searchShowAllCollections ? this.filteredCollectionsForSearch().length : 5), (collection: CollectionItem) => {
            this.CollectionRow(collection);
          }, (collection: CollectionItem) => `search-collection-${collection.id}`);
          if (this.filteredCollectionsForSearch().length > 5) {
            Button(this.searchShowAllCollections ? 'Show Less' : 'Show More')
              .fontColor(this.accentColor())
              .backgroundColor(this.cardColor())
              .borderRadius(10)
              .onClick(() => {
                this.searchShowAllCollections = !this.searchShowAllCollections;
              });
          }

          this.SearchGroup('Tags', this.filteredTagsForSearch().length);
          ForEach(this.filteredTagsForSearch().slice(0, this.searchShowAllTags ? this.filteredTagsForSearch().length : 10), (tag: string) => {
            this.TagListRow(tag);
          }, (tag: string) => `search-tag-${tag}`);
          if (this.filteredTagsForSearch().length > 10) {
            Button(this.searchShowAllTags ? 'Show Less' : 'Show More')
              .fontColor(this.accentColor())
              .backgroundColor(this.cardColor())
              .borderRadius(10)
              .onClick(() => {
                this.searchShowAllTags = !this.searchShowAllTags;
              });
          }
        }
      }
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ bottom: 96 });
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off);
  }

  @Builder
  private SearchGroup(title: string, total: number) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor());
      Text(`${total}`)
        .fontSize(12)
        .fontColor(this.secondaryTextColor());
    }
    .width('100%');
  }

  @Builder
  private TagListRow(tag: string) {
    Row({ space: 0 }) {
      Text('#')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.accentColor())
        .padding({ left: 14, right: 4 });

      Text(tag)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      Text(`${this.tagUsageCount(tag)}`)
        .fontSize(12)
        .fontColor(this.secondaryTextColor())
        .padding({ left: 8, right: 14, top: 12, bottom: 12 });
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.cardColor())
    .borderRadius(12)
    .onClick(() => {
      this.navigateToTag(tag);
    });
  }

  @Builder
  private AddLinkComposer() {
    Column({ space: 16 }) {
      Column({ space: 12 }) {
        Text('Link')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);

        TextInput({ placeholder: 'Paste a URL or text containing a URL', text: this.newLinkUrl })
          .onChange((value: string) => {
            this.handleNewLinkUrlChange(value);
          })
          .backgroundColor(this.surfaceColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(10)
          .width('100%');

        if (this.newLinkUrl.trim().length > 0) {
          Text(this.detectedUrlSummaryText())
            .fontSize(12)
            .fontColor(this.draftHasResolvedUrl() ? this.secondaryTextColor() : this.dangerColor())
            .width('100%')
            .textAlign(TextAlign.Start);
        }

        TextInput({ placeholder: 'Title (optional)', text: this.newLinkTitle })
          .onChange((value: string) => {
            this.handleNewLinkTitleChange(value);
          })
          .backgroundColor(this.surfaceColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(10)
          .width('100%');
      }
      .padding(16)
      .backgroundColor(this.cardColor())
      .borderRadius(16)
      .width('100%');

      Column({ space: 12 }) {
        Text('Collection')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);

        this.CollectionPickerTrigger(
          this.collectionLabelForQuery(this.newLinkCollectionQuery),
          this.collectionHintForQuery(this.newLinkCollectionQuery),
          () => {
            this.openCollectionPicker('add');
          }
        );
      }
      .padding(16)
      .backgroundColor(this.cardColor())
      .borderRadius(16)
      .width('100%');

      this.DraftTagEditor();

      Button(this.loading ? 'Adding...' : 'Add Link')
        .width('100%')
        .height(52)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .backgroundColor(this.primaryActionBackgroundColor())
        .fontColor(this.primaryActionTextColor())
        .borderRadius(16)
        .border({ width: 1, color: this.accentColor() })
        .shadow({ radius: 14, color: this.primaryActionShadowColor(), offsetX: 0, offsetY: 8 })
        .enabled(!this.loading)
        .onClick(() => {
          this.handleAddLink();
        });
    }
    .width('100%');
  }

  @Builder
  private CollectionPickerTrigger(value: string, hint: string, onClick: () => void) {
    Row({ space: 12 }) {
      Text('📁')
        .fontSize(18);

      Column({ space: 3 }) {
        Text(value)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);

        Text(hint)
          .fontSize(12)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);

      Text('›')
        .fontSize(24)
        .fontColor(this.secondaryTextColor())
        .fontWeight(FontWeight.Lighter);
    }
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor(this.surfaceColor())
    .width('100%')
    .onClick(onClick);
  }

  @Builder
  private DraftTagEditor() {
    Column({ space: 10 }) {
      Text('Tags')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Start);

      if (this.parsedDraftTags().length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.parsedDraftTags(), (tag: string) => {
              this.TagChoiceChip(tag, true, () => {
                this.handleDraftTagToggle(tag);
              });
            }, (tag: string) => `draft-sel-${tag}`);
          }
          .alignItems(VerticalAlign.Center);
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%');

        Row()
          .width('100%')
          .height(1)
          .backgroundColor(this.secondaryTextColor())
          .opacity(0.12);
      }

      Row({ space: 10 }) {
        TextInput({ placeholder: 'Search or create tag…', text: this.newTagPickerQuery })
          .onChange((value: string) => {
            this.newTagPickerQuery = value;
          })
          .layoutWeight(1)
          .backgroundColor(this.surfaceColor())
          .fontColor(this.primaryTextColor())
          .borderRadius(10);

        if (this.normalizedTagCandidate(this.newTagPickerQuery).length > 0) {
          Button('＋')
            .fontSize(18)
            .width(40)
            .height(40)
            .padding(0)
            .backgroundColor(this.tabActiveColor())
            .fontColor(this.tabActiveTextColor())
            .borderRadius(10)
            .onClick(() => {
              this.newLinkTagsInput = this.appendTagToInput(this.newLinkTagsInput, this.newTagPickerQuery);
              this.newTagPickerQuery = '';
            });
        }

        if (this.parsedDraftTags().length > 0) {
          Button('✕')
            .fontSize(13)
            .width(34)
            .height(40)
            .padding(0)
            .backgroundColor('transparent')
            .fontColor(this.dangerColor())
            .borderRadius(10)
            .onClick(() => {
              this.newLinkTagsInput = '';
              this.newTagPickerQuery = '';
            });
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.quickTagOptions(this.newTagPickerQuery, this.parsedDraftTags()).length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.quickTagOptions(this.newTagPickerQuery, this.parsedDraftTags()), (tag: string) => {
              this.TagChoiceChip(
                tag,
                this.parsedDraftTags().some((s: string) => s.toLowerCase() === tag.toLowerCase()),
                () => {
                  this.handleDraftTagToggle(tag);
                }
              );
            }, (tag: string) => `draft-opt-${tag}`);
          }
          .alignItems(VerticalAlign.Center);
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%');
      }
    }
    .padding(16)
    .backgroundColor(this.cardColor())
    .borderRadius(16)
    .width('100%');
  }

  @Builder
  private EditTagEditor() {
    Column({ space: 10 }) {
      Text('Tags')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Start);

      if (this.parsedEditTags().length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.parsedEditTags(), (tag: string) => {
              this.TagChoiceChip(tag, true, () => {
                this.handleEditTagToggle(tag);
              });
            }, (tag: string) => `edit-sel-${tag}`);
          }
          .alignItems(VerticalAlign.Center);
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%');

        Row()
          .width('100%')
          .height(1)
          .backgroundColor(this.secondaryTextColor())
          .opacity(0.12);
      }

      Row({ space: 10 }) {
        TextInput({ placeholder: 'Search or create tag…', text: this.editTagPickerQuery })
          .onChange((value: string) => {
            this.editTagPickerQuery = value;
          })
          .layoutWeight(1)
          .backgroundColor(this.surfaceColor())
          .borderRadius(10);

        if (this.normalizedTagCandidate(this.editTagPickerQuery).length > 0) {
          Button('＋')
            .fontSize(18)
            .width(40)
            .height(40)
            .padding(0)
            .backgroundColor(this.tabActiveColor())
            .fontColor(this.tabActiveTextColor())
            .borderRadius(10)
            .onClick(() => {
              this.editTagsInput = this.appendTagToInput(this.editTagsInput, this.editTagPickerQuery);
              this.editTagPickerQuery = '';
            });
        }

        if (this.parsedEditTags().length > 0) {
          Button('✕')
            .fontSize(13)
            .width(34)
            .height(40)
            .padding(0)
            .backgroundColor('transparent')
            .fontColor(this.dangerColor())
            .borderRadius(10)
            .onClick(() => {
              this.editTagsInput = '';
              this.editTagPickerQuery = '';
            });
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center);

      if (this.quickTagOptions(this.editTagPickerQuery, this.parsedEditTags()).length > 0) {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.quickTagOptions(this.editTagPickerQuery, this.parsedEditTags()), (tag: string) => {
              this.TagChoiceChip(
                tag,
                this.parsedEditTags().some((s: string) => s.toLowerCase() === tag.toLowerCase()),
                () => {
                  this.handleEditTagToggle(tag);
                }
              );
            }, (tag: string) => `edit-opt-${tag}`);
          }
          .alignItems(VerticalAlign.Center);
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%');
      }
    }
    .padding(16)
    .backgroundColor(this.cardColor())
    .borderRadius(16)
    .width('100%');
  }

  @Builder
  private TagChoiceChip(tag: string, selected: boolean, onClick: () => void) {
    Button(`#${tag}`)
      .fontSize(13)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(selected ? this.tabActiveTextColor() : this.primaryTextColor())
      .backgroundColor(selected ? this.tabActiveColor() : this.surfaceColor())
      .borderRadius(999)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .height(40)
      .margin({ right: 8 })
      .onClick(onClick);
  }

  @Builder
  private DashboardPanel() {
    Column({ space: 10 }) {
      this.DashboardShortcuts();

      this.HorizontalLinkStrip(
        '📌 Pinned Links',
        this.pinnedLinks.slice(0, 10),
        'No pinned links.',
        () => {
          this.navigateToPinnedLinks();
        }
      );

      this.HorizontalLinkStrip(
        '🕘 Recent Links',
        this.dashboardLinks.slice(0, 10),
        this.dashboardLoading && this.dashboardLinks.length === 0 ? 'Loading dashboard...' : 'No recent links yet.',
        () => {
          this.navigateToRecentLinks();
        }
      );

      if (this.collectionPreviewSections().length === 0) {
        this.SectionLinkTitle('Collections', () => {
          this.navigateToCollections();
        });

        Text('No collection previews yet.')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);
      } else {
        ForEach(this.collectionPreviewSections(), (section: CollectionPreviewSection) => {
          this.CollectionPreviewSection(section);
        }, (section: CollectionPreviewSection) => `dashboard-collection-strip-${section.collection.id}`);
      }
    }
    .width('100%');
  }

  @Builder
  private DashboardShortcuts() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.DashboardShortcutCard('Links', '🔗', this.formatCount(this.linksTotal), () => {
          this.navigateToAllLinks();
        });
        this.DashboardShortcutCard('Collections', '🗂', this.formatCollectionsCount(), () => {
          this.navigateToCollections();
        });
      }
      .width('100%');

      Row({ space: 8 }) {
        this.DashboardShortcutCard('Tags', '#', this.formatCount(this.tagsTotal), () => {
          this.navigateToTags();
        });
        this.DashboardShortcutCard('Pinned', '📌', this.formatCount(this.pinnedTotal), () => {
          this.navigateToPinnedLinks();
        });
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private DashboardShortcutCard(title: string, icon: string, value: string, onClick: () => void) {
    Row({ space: 10 }) {
      Text(icon)
        .fontSize(20)
        .width(28)
        .textAlign(TextAlign.Center);

      Column({ space: 2 }) {
        Text(title)
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);

        Text(value)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.cardColor())
    .borderRadius(14)
    .onClick(() => {
      onClick();
    });
  }

  @Builder
  private StatCard(title: string, value: string, onClick: () => void) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(12)
        .fontColor(this.secondaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Start);
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Start);
    }
    .layoutWeight(1)
    .padding(10)
    .backgroundColor(this.cardColor())
    .borderRadius(10)
    .onClick(() => {
      onClick();
    });
  }

  @Builder
  private InlineActionButton(symbol: string, onClick: () => void) {
    Button() {
      Text(symbol)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tabActiveTextColor())
        .width('100%')
        .textAlign(TextAlign.Center);
    }
    .width(40)
    .height(40)
    .backgroundColor(this.tabActiveColor())
    .borderRadius(20)
    .padding(0)
    .onClick(() => {
      onClick();
    });
  }

  @Builder
  private LinkCard(item: LinkItem) {
    Column({ space: 0 }) {
      // Title row
      Row({ space: 8 }) {
        Text(item.name.length > 0 ? item.name : item.url)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Start);

        if (item.pinned) {
          Text('📌')
            .fontSize(13);
        }
      }
      .width('100%')
      .padding({ bottom: 4 });

      // URL
      Text(item.url)
        .fontSize(11)
        .fontColor(this.secondaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
        .opacity(0.8);

      // Description (if any)
      if (item.description.length > 0) {
        Text(item.description)
          .fontSize(12)
          .fontColor(this.secondaryTextColor())
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ top: 4 });
      }

      // Meta row: collection chip + date
      Row({ space: 6 }) {
        Text(item.collectionName.length > 0 ? item.collectionName : 'Unorganized')
          .fontSize(11)
          .fontColor(item.collectionColor.length > 0 ? item.collectionColor : this.accentColor())
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.inputBackgroundColor())
          .borderRadius(999)
          .maxLines(1);

        if (item.tags.length > 0) {
          Text(item.tags.map((tag) => `#${tag.name}`).join(' '))
            .fontSize(11)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
        } else {
          Blank().layoutWeight(1);
        }

        if (item.createdAt.length > 0) {
          Text(this.formatDateLabel(item.createdAt))
            .fontSize(11)
            .fontColor(this.secondaryTextColor())
            .opacity(0.7);
        }
      }
      .width('100%')
      .padding({ top: 8 })
      .alignItems(VerticalAlign.Center);
    }
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(
      this.highlightedLinkId === item.id
        ? this.newlyAddedCardColor()
        : (this.selectedLink.id === item.id ? this.selectedCardColor() : this.cardColor())
    )
    .borderRadius(14)
    .width('100%')
    .onClick(() => {
      this.highlightedLinkId = 0;
      this.openLinkInBrowser(item.url);
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.highlightedLinkId = 0;
          this.handleLinkLongPress(item);
        })
    );
  }

  @Builder
  private LinkStripCard(item: LinkItem) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(item.name.length > 0 ? item.name : item.url)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start);

        if (item.pinned) {
          Text('Pin')
            .fontSize(11)
            .fontColor(this.accentColor());
        }
      }
      .width('100%');

      Text(item.collectionName.length > 0 ? item.collectionName : 'Unorganized')
        .fontSize(12)
        .fontColor(item.collectionColor.length > 0 ? item.collectionColor : this.accentColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start);

      Text(item.url)
        .fontSize(11)
        .fontColor(this.secondaryTextColor())
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start);
    }
    .width(260)
    .height(124)
    .padding(12)
    .backgroundColor(this.cardColor())
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.highlightedLinkId = 0;
      this.openLinkInBrowser(item.url);
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.highlightedLinkId = 0;
          this.handleLinkLongPress(item);
        })
    );
  }

  @Builder
  private HorizontalLinkStrip(title: string, items: Array<LinkItem>, emptyText: string, onNavigate: () => void) {
    Column({ space: 8 }) {
      this.SectionLinkTitle(title, onNavigate);

      if (items.length === 0) {
        Text(emptyText)
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);
      } else {
        List({ space: 10 }) {
          ForEach(items, (item: LinkItem) => {
            ListItem() {
              this.LinkStripCard(item);
            }
          }, (item: LinkItem) => `${title}-${item.id}`);
        }
        .listDirection(Axis.Horizontal)
        .width('100%')
        .height(140)
        .scrollBar(BarState.Off)
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST,
        });
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%');
  }

  @Builder
  private SectionLinkTitle(title: string, onClick: () => void) {
    Row({ space: 8 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .layoutWeight(1)
        .textAlign(TextAlign.Start);

      Button('View all')
        .backgroundColor(Color.Transparent)
        .fontColor(this.secondaryTextColor())
        .fontSize(12)
        .borderRadius(999)
        .padding({ left: 2, right: 2, top: 0, bottom: 0 })
        .height(24)
        .onClick(() => {
          onClick();
        });
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center);
  }

  @Builder
  private CollectionPreviewSection(section: CollectionPreviewSection) {
    Column({ space: 8 }) {
      this.SectionLinkTitle(section.collection.name.length > 0 ? section.collection.name : 'Untitled', () => {
        this.navigateToCollection(section.collection.id);
      });

      List({ space: 10 }) {
        ForEach(section.links, (item: LinkItem) => {
          ListItem() {
            this.LinkStripCard(item);
          }
        }, (item: LinkItem) => `collection-strip-${section.collection.id}-${item.id}`);
      }
      .listDirection(Axis.Horizontal)
      .width('100%')
      .height(140)
      .scrollBar(BarState.Off)
      .nestedScroll({
        scrollForward: NestedScrollMode.PARENT_FIRST,
        scrollBackward: NestedScrollMode.SELF_FIRST,
      });
    }
    .width('100%');
  }

  @Builder
  private CollectionMatchHints(query: string, matches: Array<CollectionItem>, onPick: (name: string) => void, summary: string) {
    if (query.trim().length > 0) {
      Text(summary)
        .fontSize(12)
        .fontColor(matches.length > 0 ? this.secondaryTextColor() : this.dangerColor())
        .width('100%')
        .textAlign(TextAlign.Start);

      if (matches.length > 0) {
        Row({ space: 8 }) {
          ForEach(matches.slice(0, 3), (collection: CollectionItem) => {
            Button(collection.name)
              .backgroundColor(this.cardColor())
              .fontColor(this.primaryTextColor())
              .borderRadius(999)
              .padding({ left: 10, right: 10, top: 2, bottom: 2 })
              .onClick(() => {
                onPick(collection.name);
              });
          }, (collection: CollectionItem) => `collection-match-${collection.id}`);
        }
        .width('100%');
      }
    }
  }

  @Builder
  private CollectionRow(collection: CollectionItem) {
    Row({ space: 0 }) {
      // Name + description
      Column({ space: 2 }) {
        Text(collection.name.length > 0 ? collection.name : 'Untitled')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start);

        if (collection.parentName.length > 0 || collection.description.length > 0) {
          Text(collection.parentName.length > 0 ? collection.parentName : collection.description)
            .fontSize(11)
            .fontColor(this.secondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .textAlign(TextAlign.Start);
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, top: 10, bottom: 10 });

      // Link count badge
      Text(`${collection.linkCount}`)
        .fontSize(12)
        .fontColor(this.secondaryTextColor())
        .padding({ left: 8, right: 12, top: 10, bottom: 10 });
    }
    .width('100%')
    .backgroundColor(this.cardColor())
    .borderRadius(12)
    .border({
      width: { left: 4 },
      color: collection.color.length > 0 ? collection.color : this.accentColor(),
      radius: 12,
    })
    .clip(true)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.navigateToCollection(collection.id);
    });
  }

  @Builder
  private AddLinkOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeCurrentModal();
        });

      Column() {
        Row()
          .width(44)
          .height(4)
          .borderRadius(999)
          .backgroundColor(this.secondaryTextColor())
          .opacity(0.25)
          .alignSelf(ItemAlign.Center)
          .margin({ top: 12, bottom: 6 });

        Row() {
          Text('Add Link')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Start);

          Button('✕')
            .fontSize(15)
            .width(34)
            .height(34)
            .backgroundColor(this.cardColor())
            .fontColor(this.secondaryTextColor())
            .borderRadius(999)
            .padding(0)
            .onClick(() => {
              this.closeCurrentModal();
            });
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 16 });

        Scroll() {
          Column({ space: 16 }) {
            this.AddLinkComposer();
          }
          .width('100%')
          .padding({ bottom: 24 });
        }
        .width('100%')
        .scrollBar(BarState.Off);
      }
      .onClick(() => {})
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.surfaceColor())
      .borderRadius({ topLeft: 24, topRight: 24 })
      .constraintSize({ maxHeight: '92%' });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private EditLinkOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeCurrentModal();
        });

      Column() {
        Row()
          .width(44)
          .height(4)
          .borderRadius(999)
          .backgroundColor(this.secondaryTextColor())
          .opacity(0.25)
          .alignSelf(ItemAlign.Center)
          .margin({ top: 12, bottom: 6 });

        Row() {
          Text(this.detailLoading ? 'Loading...' : 'Edit Link')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.primaryTextColor())
            .layoutWeight(1)
            .textAlign(TextAlign.Start);

          Button('✕')
            .fontSize(15)
            .width(34)
            .height(34)
            .backgroundColor(this.cardColor())
            .fontColor(this.secondaryTextColor())
            .borderRadius(999)
            .padding(0)
            .onClick(() => {
              this.closeCurrentModal();
            });
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 16 });

        Scroll() {
          Column({ space: 16 }) {
            this.DetailPanel();
          }
          .width('100%')
          .padding({ bottom: 24 });
        }
        .width('100%')
        .scrollBar(BarState.Off);
      }
      .onClick(() => {})
      .width('100%')
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.surfaceColor())
      .borderRadius({ topLeft: 24, topRight: 24 })
      .constraintSize({ maxHeight: '92%' });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private CollectionOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeCurrentModal();
        });

      Column({ space: 12 }) {
        Row() {
          Column({ space: 4 }) {
            Text('Create Collection')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start);

            Text('Create it here and return to the link form.')
              .fontSize(12)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start);
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          Button('Back')
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .borderRadius(999)
            .onClick(() => {
              this.closeCurrentModal();
            });
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        Column({ space: 10 }) {
          TextInput({ placeholder: 'Name', text: this.newCollectionName })
            .onChange((value: string) => {
              this.newCollectionName = value;
            })
            .width('100%');

          TextInput({ placeholder: 'Description (optional)', text: this.newCollectionDescription })
            .onChange((value: string) => {
              this.newCollectionDescription = value;
            })
            .height(88)
            .width('100%');

          TextInput({ placeholder: 'Parent collection (optional)', text: this.newCollectionParentQuery })
            .onChange((value: string) => {
              this.newCollectionParentQuery = value;
            })
            .width('100%');

          if (this.newCollectionParentQuery.trim().length > 0) {
            Text(this.detectedParentCollectionSummaryText())
              .fontSize(12)
              .fontColor(this.matchedParentCollection() !== null ? this.secondaryTextColor() : this.dangerColor())
              .width('100%')
              .textAlign(TextAlign.Start);
          }

          Row({ space: 8 }) {
            this.ColorChip('#2563eb');
            this.ColorChip('#0f766e');
            this.ColorChip('#dc2626');
            this.ColorChip('#7c3aed');
            this.ColorChip('#f59e0b');
          }
          .width('100%');

          Text(`Color: ${this.newCollectionColor}`)
            .fontSize(12)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);
        }
        .padding(14)
        .backgroundColor(this.cardColor())
        .borderRadius(14)
        .width('100%');

        Row({ space: 8 }) {
          Button('Reset')
            .layoutWeight(1)
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .borderRadius(12)
            .onClick(() => {
              this.resetCollectionDraft();
            });

          Button(this.collectionSaving ? 'Creating...' : 'Create')
            .layoutWeight(1)
            .backgroundColor(this.tabActiveColor())
            .fontColor(this.tabActiveTextColor())
            .borderRadius(12)
            .enabled(!this.collectionSaving)
            .onClick(() => {
              this.handleCreateCollection();
            });
        }
        .width('100%');
      }
      .onClick(() => {})
      .width('100%')
      .padding(12)
      .backgroundColor(this.surfaceColor())
      .borderRadius({ topLeft: 20, topRight: 20 })
      .constraintSize({ maxHeight: '80%' });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private CollectionPickerOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.closeCurrentModal();
        });

      Column({ space: 12 }) {
        Row() {
          Column({ space: 4 }) {
            Text('Choose Collection')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start);

            Text('Search existing collections or create a new one.')
              .fontSize(12)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start);
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start);

          Button('Back')
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .borderRadius(999)
            .onClick(() => {
              this.closeCurrentModal();
            });
        }
        .width('100%')
        .alignItems(VerticalAlign.Center);

        TextInput({ placeholder: 'Search collections', text: this.collectionPickerQuery })
          .onChange((value: string) => {
            this.collectionPickerQuery = value;
          })
          .width('100%');

        Row({ space: 8 }) {
          Button('Unorganized')
            .layoutWeight(1)
            .backgroundColor(this.selectedCollectionPickerId() === 0 ? this.tabActiveColor() : this.cardColor())
            .fontColor(this.selectedCollectionPickerId() === 0 ? this.tabActiveTextColor() : this.primaryTextColor())
            .borderRadius(12)
            .onClick(() => {
              this.selectCollectionFromPicker(null);
            });

          Button(this.collectionCreateButtonText())
            .layoutWeight(1)
            .backgroundColor(this.cardColor())
            .fontColor(this.primaryTextColor())
            .borderRadius(12)
            .onClick(() => {
              this.openCollectionCreateFromPicker();
            });
        }
        .width('100%');

        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.filteredCollectionsForPicker(), (item: CollectionItem) => {
              Row({ space: 10 }) {
                Column({ space: 4 }) {
                  Text(item.name)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.primaryTextColor())
                    .width('100%')
                    .textAlign(TextAlign.Start);

                  Text(this.collectionPickerItemHint(item))
                    .fontSize(12)
                    .fontColor(this.secondaryTextColor())
                    .width('100%')
                    .textAlign(TextAlign.Start);
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start);

                if (this.selectedCollectionPickerId() === item.id) {
                  Text('Selected')
                    .fontSize(12)
                    .fontColor(this.accentColor());
                }
              }
              .padding({ left: 14, right: 14, top: 14, bottom: 14 })
              .backgroundColor(this.selectedCollectionPickerId() === item.id ? this.surfaceColor() : this.cardColor())
              .borderRadius(12)
              .width('100%')
              .onClick(() => {
                this.selectCollectionFromPicker(item);
              });
            }, (item: CollectionItem) => `${item.id}`);

            if (this.filteredCollectionsForPicker().length === 0) {
              Text('No collections match the current search.')
                .fontSize(12)
                .fontColor(this.secondaryTextColor())
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding(12);
            }
          }
          .width('100%');
        }
        .width('100%')
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: '58%' });
      }
      .onClick(() => {})
      .width('100%')
      .padding(12)
      .backgroundColor(this.surfaceColor())
      .borderRadius({ topLeft: 20, topRight: 20 })
      .constraintSize({ maxHeight: '85%' });
    }
    .width('100%')
    .height('100%');
  }

  @Builder
  private SettingsPanel() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 6 }) {
          this.SectionTitle('Menu');
          this.SectionSubtitle('Refine appearance, server connection, and Linkwarden shortcuts.');
        }
        .padding(18)
        .backgroundColor(this.cardColor())
        .borderRadius(18)
        .border({ width: 1, color: this.panelBorderColor() })
        .width('100%');

        Column({ space: 12 }) {
          Column({ space: 4 }) {
            Text('Linkwarden')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.primaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start);

            Text(this.instance)
              .fontSize(12)
              .fontColor(this.secondaryTextColor())
              .width('100%')
              .textAlign(TextAlign.Start)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);

          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(this.themeModeLabel())
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
              Text('Theme')
                .fontSize(10)
                .fontColor(this.secondaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
            }
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.inputBackgroundColor())
            .borderRadius(14)
            .border({ width: 1, color: this.panelBorderColor() });

            Column({ space: 2 }) {
              Text(this.formatCount(this.linksTotal))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
              Text('Links')
                .fontSize(10)
                .fontColor(this.secondaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
            }
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.inputBackgroundColor())
            .borderRadius(14)
            .border({ width: 1, color: this.panelBorderColor() });
          }
          .width('100%');

          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text(this.formatCount(this.tagsTotal))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
              Text('Tags')
                .fontSize(10)
                .fontColor(this.secondaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
            }
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.inputBackgroundColor())
            .borderRadius(14)
            .border({ width: 1, color: this.panelBorderColor() });

            Column({ space: 2 }) {
              Text(this.formatCount(this.pinnedTotal))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.primaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
              Text('Pinned')
                .fontSize(10)
                .fontColor(this.secondaryTextColor())
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1);
            }
            .layoutWeight(1)
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(this.inputBackgroundColor())
            .borderRadius(14)
            .border({ width: 1, color: this.panelBorderColor() });
          }
          .width('100%');
        }
        .padding(18)
        .backgroundColor(this.cardColor())
        .borderRadius(18)
        .border({ width: 1, color: this.panelBorderColor() })
        .width('100%');

        Column({ space: 10 }) {
          Text('Appearance')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          this.ThemePicker();
        }
        .padding(18)
        .backgroundColor(this.cardColor())
        .borderRadius(18)
        .border({ width: 1, color: this.panelBorderColor() })
        .width('100%');

        Column({ space: 10 }) {
          Text('Server')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          Text('Change server endpoint. Saving a new server signs current session out.')
            .fontSize(12)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          TextInput({ placeholder: 'Server URL', text: this.settingsInstance })
            .onChange((value: string) => {
              this.settingsInstance = value;
            })
            .backgroundColor(this.inputBackgroundColor())
            .fontColor(this.primaryTextColor())
            .borderRadius(12)
            .width('100%');

          Button('Apply Server')
            .width('100%')
            .height(44)
            .backgroundColor(this.themePalette().accentSoft)
            .fontColor(this.accentColor())
            .borderRadius(14)
            .border({ width: 1, color: this.accentColor() })
            .onClick(() => {
              this.handleSaveSettings();
            });
        }
        .padding(18)
        .backgroundColor(this.cardColor())
        .borderRadius(18)
        .border({ width: 1, color: this.panelBorderColor() })
        .width('100%');

        Column({ space: 10 }) {
          Text('Quick Links')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          Row({ space: 10 }) {
            this.MenuActionTile('Website', 'Open product site', () => {
              this.openLinkInBrowser('https://linkwarden.app');
            });
            this.MenuActionTile('Repository', 'Open GitHub repo', () => {
              this.openLinkInBrowser('https://github.com/linkwarden/linkwarden');
            });
          }
          .width('100%');
        }
        .padding(18)
        .backgroundColor(this.cardColor())
        .borderRadius(18)
        .border({ width: 1, color: this.panelBorderColor() })
        .width('100%');

        Column({ space: 10 }) {
          Text('Session')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          Text('Sign out from current Linkwarden account on this device.')
            .fontSize(12)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          Button('Sign Out')
            .width('100%')
            .height(44)
            .backgroundColor('transparent')
            .fontColor(this.dangerColor())
            .borderRadius(14)
            .border({ width: 1, color: this.dangerColor() })
            .onClick(() => {
              this.handleSignOut();
            });
        }
        .padding(18)
        .backgroundColor(this.cardColor())
        .borderRadius(18)
        .border({ width: 1, color: this.panelBorderColor() })
        .width('100%');

        Text('HarmonyOS Native Client')
          .fontSize(12)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start);
      }
      .padding({ left: 12, right: 12, top: 12, bottom: 108 })
      .width('100%');
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off);
  }

  @Builder
  private ThemePicker() {
    Column({ space: 8 }) {
      Text('Theme')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor())
        .width('100%')
        .textAlign(TextAlign.Start);

      Row({ space: 8 }) {
        ForEach(createThemeOptions(), (option: ThemeOption) => {
          this.ThemeOptionButton(option.mode, option.title, option.subtitle);
        }, (option: ThemeOption) => option.mode);
      }
      .width('100%');
    }
    .width('100%');
  }

  @Builder
  private ThemeOptionButton(mode: ThemeMode, title: string, subtitle: string) {
    Button() {
      Column({ space: 4 }) {
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isThemeOptionSelected(mode) ? this.tabActiveTextColor() : this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1);

        Text(subtitle)
          .fontSize(11)
          .fontColor(this.isThemeOptionSelected(mode) ? this.tabActiveTextColor() : this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);
    }
    .layoutWeight(1)
    .padding(12)
    .backgroundColor(this.isThemeOptionSelected(mode) ? this.tabActiveColor() : this.inputBackgroundColor())
    .borderRadius(14)
    .border({ width: 1, color: this.isThemeOptionSelected(mode) ? this.tabActiveColor() : this.panelBorderColor() })
    .onClick(() => {
      this.themeMode = mode;
      this.persistSessionState().catch((e: Object) => {
        console.warn('Theme persist failed: ' + String(e));
      });
    });
  }

  @Builder
  private MenuMetricPill(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor())
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(1);

      Text(label)
        .fontSize(10)
        .fontColor(this.secondaryTextColor())
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(this.inputBackgroundColor())
    .borderRadius(14)
    .border({ width: 1, color: this.panelBorderColor() });
  }

  @Builder
  private MenuActionTile(title: string, subtitle: string, onClick: () => void) {
    Button() {
      Column({ space: 6 }) {
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        Text(subtitle)
          .fontSize(11)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start);
    }
    .layoutWeight(1)
    .padding(14)
    .backgroundColor(this.inputBackgroundColor())
    .borderRadius(14)
    .border({ width: 1, color: this.panelBorderColor() })
    .onClick(() => {
      onClick();
    });
  }

  @Builder
  private DetailPanel() {
    Column({ space: 16 }) {
      if (!this.detailLoading && this.selectedLink.id > 0) {
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Column({ space: 4 }) {
              Text(this.selectedLink.collectionName.length > 0 ? this.selectedLink.collectionName : 'Unorganized')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.selectedLink.collectionColor.length > 0 ? this.selectedLink.collectionColor : this.accentColor())
                .textAlign(TextAlign.Start);

              if (this.selectedLink.createdAt.length > 0) {
                Text(`Saved ${this.formatDateLabel(this.selectedLink.createdAt)}`)
                  .fontSize(12)
                  .fontColor(this.secondaryTextColor())
                  .textAlign(TextAlign.Start);
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start);

            Button(this.pinSaving ? '…' : (this.editPinned ? '📌 Pinned' : 'Pin'))
              .fontSize(13)
              .height(34)
              .backgroundColor(this.editPinned ? this.tabActiveColor() : this.surfaceColor())
              .fontColor(this.editPinned ? this.tabActiveTextColor() : this.primaryTextColor())
              .borderRadius(999)
              .enabled(!this.pinSaving && !this.detailSaving && !this.detailDeleting)
              .onClick(() => {
                this.handleTogglePin();
              });
          }
          .width('100%')
          .alignItems(VerticalAlign.Center);
        }
        .padding(16)
        .backgroundColor(this.cardColor())
        .borderRadius(16)
        .width('100%');

        Column({ space: 12 }) {
          Text('Link')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          TextInput({ placeholder: 'Title', text: this.editName })
            .onChange((value: string) => {
              this.editName = value;
            })
            .backgroundColor(this.surfaceColor())
            .borderRadius(10)
            .width('100%');

          TextInput({ placeholder: 'URL', text: this.editUrl })
            .onChange((value: string) => {
              this.editUrl = value;
            })
            .backgroundColor(this.surfaceColor())
            .borderRadius(10)
            .width('100%');

          TextInput({ placeholder: 'Description', text: this.editDescription })
            .onChange((value: string) => {
              this.editDescription = value;
            })
            .height(96)
            .backgroundColor(this.surfaceColor())
            .borderRadius(10)
            .width('100%');
        }
        .padding(16)
        .backgroundColor(this.cardColor())
        .borderRadius(16)
        .width('100%');

        Column({ space: 12 }) {
          Text('Collection')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.secondaryTextColor())
            .width('100%')
            .textAlign(TextAlign.Start);

          this.CollectionPickerTrigger(
            this.collectionLabelForQuery(this.editCollectionQuery),
            this.collectionHintForQuery(this.editCollectionQuery),
            () => {
              this.openCollectionPicker('edit');
            }
          );
        }
        .padding(16)
        .backgroundColor(this.cardColor())
        .borderRadius(16)
        .width('100%');

        this.EditTagEditor();

        Button(this.detailSaving ? 'Saving...' : 'Save Changes')
          .width('100%')
          .height(50)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(this.tabActiveColor())
          .fontColor(this.tabActiveTextColor())
          .borderRadius(14)
          .enabled(!this.detailSaving && !this.detailDeleting)
          .onClick(() => {
            this.handleSaveLink();
          });

        Button(this.detailDeleting ? 'Deleting...' : 'Delete Link')
          .width('100%')
          .height(44)
          .fontSize(14)
          .backgroundColor('transparent')
          .fontColor(this.dangerColor())
          .borderRadius(14)
          .enabled(!this.detailSaving && !this.detailDeleting)
          .onClick(() => {
            this.handleDeleteLink();
          });
      } else {
        Text('Loading detail...')
          .fontSize(13)
          .fontColor(this.secondaryTextColor())
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding(12);
      }
    }
    .width('100%');
  }

  @Builder
  private SectionTitle(value: string) {
    Text(value)
      .fontSize(20)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.primaryTextColor())
      .width('100%')
      .textAlign(TextAlign.Start);
  }

  @Builder
  private SectionSubtitle(value: string) {
    Text(value)
      .fontSize(12)
      .fontColor(this.secondaryTextColor())
      .width('100%')
      .textAlign(TextAlign.Start);
  }

  @Builder
  private ColorChip(color: string) {
    Button('')
      .width(28)
      .height(28)
      .backgroundColor(color)
      .borderRadius(14)
      .border({ width: this.newCollectionColor === color ? 2 : 0, color: this.primaryTextColor() })
      .onClick(() => {
        this.newCollectionColor = color;
      });
  }

  private mergeTagsFromLinks(links: Array<LinkItem>): void {
    const existingKeys = new Set(this.knownTagNames.map((t) => t.toLowerCase()));
    const additions: Array<string> = [];
    links.forEach((item: LinkItem) => {
      item.tags.forEach((tag) => {
        const value = tag.name.trim();
        if (value.length > 0) {
          const key = value.toLowerCase();
          if (!existingKeys.has(key)) {
            existingKeys.add(key);
            additions.push(value);
          }
        }
      });
    });
    if (additions.length > 0) {
      this.knownTagNames = [...this.knownTagNames, ...additions].sort((a, b) =>
        a.toLowerCase().localeCompare(b.toLowerCase())
      );
    }
  }

  private mergeTagNamesFromTags(tags: Array<LinkTag>): void {
    const names = tags
      .map((tag) => tag.name.trim())
      .filter((name) => name.length > 0);
    const existingKeys = new Set(this.knownTagNames.map((t) => t.toLowerCase()));
    const additions: Array<string> = [];
    names.forEach((name) => {
      const key = name.toLowerCase();
      if (!existingKeys.has(key)) {
        existingKeys.add(key);
        additions.push(name);
      }
    });
    if (additions.length > 0) {
      this.knownTagNames = [...this.knownTagNames, ...additions].sort((a, b) =>
        a.toLowerCase().localeCompare(b.toLowerCase())
      );
    }
  }

  private uniqueTags(): Array<string> {
    return this.knownTagNames;
  }

  private formatCount(value: number): string {
    return value < 0 ? '–' : `${value}`;
  }

  private formatCollectionsCount(): string {
    if (this.collections.length > 0) {
      return `${this.collections.length}`;
    }
    return this.dashboardLoading ? '–' : '0';
  }

  private activeCollectionName(): string {
    const id = this.selectedCollectionFilterId;
    const matches = this.collections.filter((c: CollectionItem) => c.id === id);
    return matches.length > 0 ? matches[0].name : `Collection #${id}`;
  }

  private filteredCollections(): Array<CollectionItem> {
    const query = this.collectionSearchQuery.trim().toLowerCase();
    if (query.length === 0) {
      return this.collections;
    }

    return this.collections.filter((item) => item.name.toLowerCase().indexOf(query) >= 0);
  }

  private filteredTags(): Array<string> {
    const query = this.tagSearchQuery.trim().toLowerCase();
    const tags = this.uniqueTags();
    if (query.length === 0) {
      return tags;
    }

    return tags.filter((tag) => tag.indexOf(query) >= 0);
  }

  private filteredLinksForSearch(): Array<LinkItem> {
    const query = this.searchPageQuery.trim().toLowerCase();
    if (query.length === 0) {
      return [];
    }

    return this.links.filter((item) => {
      const inTitle = item.name.toLowerCase().indexOf(query) >= 0;
      const inUrl = item.url.toLowerCase().indexOf(query) >= 0;
      const inDesc = item.description.toLowerCase().indexOf(query) >= 0;
      const inTags = item.tags.some((tag) => tag.name.toLowerCase().indexOf(query) >= 0);
      return inTitle || inUrl || inDesc || inTags;
    });
  }

  private filteredCollectionsForSearch(): Array<CollectionItem> {
    const query = this.searchPageQuery.trim().toLowerCase();
    if (query.length === 0) {
      return [];
    }

    return this.collections.filter((item) => item.name.toLowerCase().indexOf(query) >= 0);
  }

  private filteredTagsForSearch(): Array<string> {
    const query = this.searchPageQuery.trim().toLowerCase();
    if (query.length === 0) {
      return [];
    }

    return this.uniqueTags().filter((tag) => tag.indexOf(query) >= 0);
  }

  private searchHasAnyResult(): boolean {
    return this.filteredLinksForSearch().length > 0
      || this.filteredCollectionsForSearch().length > 0
      || this.filteredTagsForSearch().length > 0;
  }

  private floatingDockShadowColor(): string {
    return this.themePalette().dockShadow;
  }

  private handleQuickMenuAction(actionId: 'add' | 'search' | 'settings'): void {
    this.quickMenuOpen = false;

    if (actionId === 'add') {
      this.openAddModal();
      return;
    }

    if (actionId === 'search') {
      this.mainView = 'search';
      this.refreshLinks(true);
      this.refreshDashboard();
      return;
    }

    this.mainView = 'settings';
    this.settingsInstance = this.instance;
  }

  private mainViewTitle(): string {
    if (this.mainView === 'dashboard') {
      return 'Home';
    }

    if (this.mainView === 'elements') {
      return 'Library';
    }

    if (this.mainView === 'search') {
      return 'Search';
    }

    return 'Menu';
  }

  private mainViewSubtitle(): string {
    if (this.mainView === 'dashboard') {
      return 'Recent, pinned, and collections';
    }

    if (this.mainView === 'elements') {
      return 'Links, collections, and tags';
    }

    if (this.mainView === 'search') {
      return 'Find links, collections, and tags';
    }

    return 'Settings and shortcuts';
  }

  private handleNewLinkUrlChange(value: string): void {
    this.newLinkUrl = value;
    if (!this.newLinkTitleEdited) {
      this.newLinkTitle = this.extractUrlAndTitleFromInput(value).title;
    }
  }

  private handleNewLinkTitleChange(value: string): void {
    this.newLinkTitle = value;
    this.newLinkTitleEdited = value.trim().length > 0;
  }

  private draftHasResolvedUrl(): boolean {
    return this.extractUrlAndTitleFromInput(this.newLinkUrl).url.length > 0;
  }

  private detectedUrlSummaryText(): string {
    const parsed = this.extractUrlAndTitleFromInput(this.newLinkUrl);
    if (parsed.url.length === 0) {
      return 'No valid URL detected yet.';
    }

    return `Detected URL: ${parsed.url}`;
  }

  private matchedCollectionByQuery(rawQuery: string): CollectionItem | null {
    const query = rawQuery.trim().toLowerCase();
    if (query.length === 0) {
      return null;
    }

    const exactMatch = this.collections.find((item) => item.name.toLowerCase() === query);
    if (exactMatch !== undefined) {
      return exactMatch;
    }

    const partialMatches = this.collections.filter((item) => item.name.toLowerCase().indexOf(query) >= 0);
    if (partialMatches.length === 1) {
      return partialMatches[0];
    }

    return null;
  }

  private matchedDraftCollection(): CollectionItem | null {
    return this.matchedCollectionByQuery(this.newLinkCollectionQuery);
  }

  private draftCollectionMatches(): Array<CollectionItem> {
    const query = this.newLinkCollectionQuery.trim().toLowerCase();
    if (query.length === 0) {
      return [];
    }

    return this.collections.filter((item) => item.name.toLowerCase().indexOf(query) >= 0);
  }

  private detectedCollectionSummaryText(): string {
    const matchedCollection = this.matchedDraftCollection();
    if (matchedCollection === null) {
      return 'No matching collection found.';
    }

    return `Matched collection: ${matchedCollection.name}`;
  }

  private parsedDraftTags(): Array<string> {
    return this.parseTagsFromInput(this.newLinkTagsInput);
  }

  private matchedEditCollection(): CollectionItem | null {
    return this.matchedCollectionByQuery(this.editCollectionQuery);
  }

  private editCollectionMatches(): Array<CollectionItem> {
    const query = this.editCollectionQuery.trim().toLowerCase();
    if (query.length === 0) {
      return [];
    }

    return this.collections.filter((item) => item.name.toLowerCase().indexOf(query) >= 0);
  }

  private matchedParentCollection(): CollectionItem | null {
    return this.matchedCollectionByQuery(this.newCollectionParentQuery);
  }

  private detectedParentCollectionSummaryText(): string {
    const matchedCollection = this.matchedParentCollection();
    if (matchedCollection === null) {
      return 'No matching parent collection found.';
    }

    return `Parent collection: ${matchedCollection.name}`;
  }

  private detectedEditCollectionSummaryText(): string {
    const matchedCollection = this.matchedEditCollection();
    if (matchedCollection === null) {
      return 'No matching collection found.';
    }

    return `Matched collection: ${matchedCollection.name}`;
  }

  private parsedEditTags(): Array<string> {
    return this.parseTagsFromInput(this.editTagsInput);
  }

  private draftTagSummaryText(): string {
    return this.tagSummaryText(this.resolvedDraftTags());
  }

  private editTagSummaryText(): string {
    return this.tagSummaryText(this.resolvedEditTags());
  }

  private resolvedDraftTags(): Array<string> {
    return this.tagsIncludingPendingQuery(this.newLinkTagsInput, this.newTagPickerQuery);
  }

  private resolvedEditTags(): Array<string> {
    return this.tagsIncludingPendingQuery(this.editTagsInput, this.editTagPickerQuery);
  }

  private handleDraftTagToggle(tag: string): void {
    this.newLinkTagsInput = this.toggleTagInInput(this.newLinkTagsInput, tag);
  }

  private handleEditTagToggle(tag: string): void {
    this.editTagsInput = this.toggleTagInInput(this.editTagsInput, tag);
  }

  private normalizedTagCandidate(rawValue: string): string {
    return rawValue.trim().replace(/^#+/, '');
  }

  private normalizedTagsInput(tags: Array<string>): string {
    return tags.join(', ');
  }

  private appendTagToInput(rawInput: string, rawTag: string): string {
    const candidate = this.normalizedTagCandidate(rawTag);
    if (candidate.length === 0) {
      return rawInput;
    }

    const nextTags = this.parseTagsFromInput(rawInput);
    const exists = nextTags.some((item) => item.toLowerCase() === candidate.toLowerCase());
    if (!exists) {
      nextTags.push(candidate);
    }

    return this.normalizedTagsInput(nextTags);
  }

  private removeTagFromInput(rawInput: string, rawTag: string): string {
    const nextTags = this.parseTagsFromInput(rawInput)
      .filter((item) => item.toLowerCase() !== rawTag.trim().toLowerCase());
    return this.normalizedTagsInput(nextTags);
  }

  private toggleTagInInput(rawInput: string, rawTag: string): string {
    const exists = this.parseTagsFromInput(rawInput)
      .some((item) => item.toLowerCase() === rawTag.trim().toLowerCase());
    return exists ? this.removeTagFromInput(rawInput, rawTag) : this.appendTagToInput(rawInput, rawTag);
  }

  private parseTagsFromInput(rawInput: string): Array<string> {
    const rawItems = rawInput
      .split(/[\n,]/)
      .map((item) => this.normalizedTagCandidate(item))
      .filter((item) => item.length > 0);
    const deduped: Array<string> = [];

    rawItems.forEach((item) => {
      const exists = deduped.some((current) => current.toLowerCase() === item.toLowerCase());
      if (!exists) {
        deduped.push(item);
      }
    });

    return deduped;
  }

  private tagsIncludingPendingQuery(rawInput: string, rawQuery: string): Array<string> {
    const parsed = this.parseTagsFromInput(rawInput);
    const candidate = this.normalizedTagCandidate(rawQuery);
    if (candidate.length === 0) {
      return parsed;
    }

    const exists = parsed.some((item) => item.toLowerCase() === candidate.toLowerCase());
    if (!exists) {
      parsed.push(candidate);
    }

    return parsed;
  }

  private canCreateTag(rawQuery: string, selectedTags: Array<string>): boolean {
    const candidate = this.normalizedTagCandidate(rawQuery);
    if (candidate.length === 0) {
      return false;
    }

    const existsInSelected = selectedTags.some((tag) => tag.toLowerCase() === candidate.toLowerCase());
    const existsInLibrary = this.uniqueTags().some((tag) => tag.toLowerCase() === candidate.toLowerCase());
    return !existsInSelected && !existsInLibrary;
  }

  private pendingTagCandidate(rawQuery: string, selectedTags: Array<string>): string {
    const candidate = this.normalizedTagCandidate(rawQuery);
    if (candidate.length === 0) {
      return '';
    }

    const existsInSelected = selectedTags.some((tag) => tag.toLowerCase() === candidate.toLowerCase());
    return existsInSelected ? '' : candidate;
  }

  private quickTagOptions(rawQuery: string, selectedTags: Array<string>): Array<string> {
    const query = this.normalizedTagCandidate(rawQuery).toLowerCase();
    const options: Array<string> = [];

    selectedTags.forEach((tag) => {
      if (query.length === 0 || tag.toLowerCase().indexOf(query) >= 0) {
        options.push(tag);
      }
    });

    this.uniqueTags().forEach((tag) => {
      const exists = options.some((item) => item.toLowerCase() === tag.toLowerCase());
      if (!exists && (query.length === 0 || tag.toLowerCase().indexOf(query) >= 0)) {
        options.push(tag);
      }
    });

    return options;
  }

  private collectionLabelForQuery(rawQuery: string): string {
    const query = rawQuery.trim();
    if (query.length === 0) {
      return 'Unorganized';
    }

    const matched = this.matchedCollectionByQuery(query);
    return matched === null ? query : matched.name;
  }

  private collectionHintForQuery(rawQuery: string): string {
    const query = rawQuery.trim();
    if (query.length === 0) {
      return 'No collection will be assigned.';
    }

    const matched = this.matchedCollectionByQuery(query);
    if (matched !== null) {
      return matched.parentName.length > 0 ? `Inside ${matched.parentName}` : 'Existing collection';
    }

    return 'Not matched yet. Use picker to select or create it.';
  }

  private filteredCollectionsForPicker(): Array<CollectionItem> {
    const query = this.collectionPickerQuery.trim().toLowerCase();
    if (query.length === 0) {
      return this.collections;
    }

    return this.collections.filter((item) => item.name.toLowerCase().indexOf(query) >= 0);
  }

  private selectedCollectionPickerId(): number {
    const currentQuery = this.collectionPickerSource === 'add'
      ? this.newLinkCollectionQuery
      : this.editCollectionQuery;
    const matched = this.matchedCollectionByQuery(currentQuery);
    if (matched !== null) {
      return matched.id;
    }

    return currentQuery.trim().length === 0 ? 0 : -1;
  }

  private collectionPickerItemHint(item: CollectionItem): string {
    if (item.parentName.length > 0) {
      return `${item.linkCount} links · Parent: ${item.parentName}`;
    }

    return `${item.linkCount} links`;
  }

  private collectionCreateButtonText(): string {
    const candidate = this.collectionPickerQuery.trim();
    return candidate.length > 0 ? `New "${candidate}"` : 'New Collection';
  }

  private openCollectionPicker(source: CollectionFormSource): void {
    this.collectionPickerSource = source;
    this.collectionPickerQuery = '';
    this.activeModal = 'collection-picker';
  }

  private tagUsageCount(tagName: string): number {
    return this.links.filter((item: LinkItem) => item.tags.some((tag) => tag.name.toLowerCase() === tagName.toLowerCase())).length;
  }

  private selectCollectionFromPicker(collection: CollectionItem | null): void {
    if (this.collectionPickerSource === 'add') {
      this.newLinkCollectionQuery = collection === null ? '' : collection.name;
      this.activeModal = 'add';
      return;
    }

    this.editCollectionQuery = collection === null ? '' : collection.name;
    this.activeModal = 'edit';
  }

  private openCollectionCreateFromPicker(): void {
    if (this.collectionPickerSource === 'add') {
      this.newLinkCollectionQuery = this.collectionPickerQuery.trim();
    } else {
      this.editCollectionQuery = this.collectionPickerQuery.trim();
    }

    this.openCollectionModal(this.collectionPickerSource);
  }

  private tagSummaryText(tags: Array<string>): string {
    if (tags.length === 0) {
      return '';
    }

    const existingTags = this.uniqueTags();
    const newTags = tags.filter((tag) => !existingTags.some((item) => item.toLowerCase() === tag.toLowerCase()));
    if (newTags.length === 0) {
      return 'All tags already exist.';
    }

    return `Will create: ${newTags.map((tag) => `#${tag}`).join(' ')}`;
  }

  private clearNewLinkDraft(): void {
    this.newLinkUrl = '';
    this.newLinkTitle = '';
    this.newLinkTitleEdited = false;
    this.newLinkCollectionQuery = '';
    this.newLinkTagsInput = '';
    this.newTagPickerQuery = '';
  }

  private resetCollectionDraft(): void {
    this.newCollectionName = '';
    this.newCollectionDescription = '';
    this.newCollectionColor = '#2563eb';
    this.newCollectionParentQuery = '';
  }

  private applyNewLinkDraft(url: string, title: string = ''): void {
    this.newLinkUrl = url;
    this.newLinkTitle = title.length > 0 ? title : this.extractUrlAndTitleFromInput(url).title;
    this.newLinkTitleEdited = false;
    this.newLinkCollectionQuery = '';
    this.newLinkTagsInput = '';
    this.newTagPickerQuery = '';
  }

  private navigateToCollection(collectionId: number): void {
    this.mainView = 'elements';
    this.elementsView = 'links';
    this.selectedCollectionFilterId = collectionId;
    this.showPinnedOnly = false;
    this.refreshLinks(true);
  }

  private navigateToAllLinks(): void {
    this.mainView = 'elements';
    this.elementsView = 'links';
    this.selectedCollectionFilterId = 0;
    this.showPinnedOnly = false;
    this.refreshLinks(true);
  }

  private navigateToPinnedLinks(): void {
    this.mainView = 'elements';
    this.elementsView = 'links';
    this.selectedCollectionFilterId = 0;
    this.showPinnedOnly = true;
    this.refreshLinks(true);
  }

  private navigateToCollections(): void {
    this.mainView = 'elements';
    this.elementsView = 'collections';
    this.collectionSearchQuery = '';
    this.refreshDashboard();
  }

  private navigateToTags(): void {
    this.mainView = 'elements';
    this.elementsView = 'tags';
    this.tagSearchQuery = '';
  }

  private navigateToTag(tag: string): void {
    this.mainView = 'elements';
    this.elementsView = 'links';
    this.selectedCollectionFilterId = 0;
    this.showPinnedOnly = false;
    this.searchQuery = `#${tag}`;
    this.refreshLinks(true);
  }

  private navigateToRecentLinks(): void {
    this.mainView = 'elements';
    this.elementsView = 'links';
    this.selectedCollectionFilterId = 0;
    this.showPinnedOnly = false;
    this.refreshLinks(true);
  }

  private openAddModal(): void {
    this.newTagPickerQuery = '';
    this.activeModal = 'add';
  }

  private openCollectionModal(source: CollectionFormSource): void {
    this.collectionModalSource = source;
    this.collectionModalReturn = source === 'add' ? 'add' : 'edit';
    this.resetCollectionDraft();
    this.newCollectionName = source === 'add' ? this.newLinkCollectionQuery.trim() : this.editCollectionQuery.trim();
    this.activeModal = 'collection';
  }

  private closeCurrentModal(): void {
    if (this.activeModal === 'collection') {
      this.activeModal = this.collectionModalReturn;
      return;
    }

    if (this.activeModal === 'collection-picker') {
      this.activeModal = this.collectionPickerSource === 'add' ? 'add' : 'edit';
      return;
    }

    this.activeModal = 'none';
  }

  private collectionPreviewSections(): Array<CollectionPreviewSection> {
    const grouped: Array<CollectionPreviewSection> = [];

    this.collections.forEach((collection: CollectionItem) => {
      const links = this.homePreviewLinks
        .filter((item: LinkItem) => item.collectionId === collection.id)
        .slice(0, 10);

      if (links.length > 0) {
        grouped.push({ collection, links });
      }
    });

    const unorganizedLinks = this.homePreviewLinks
      .filter((item: LinkItem) => item.collectionId === 0)
      .slice(0, 10);

    if (unorganizedLinks.length > 0) {
      grouped.push({
        collection: {
          id: 0,
          ownerId: 0,
          name: 'Unorganized',
          description: '',
          color: '',
          parentId: 0,
          parentName: '',
          linkCount: unorganizedLinks.length,
        },
        links: unorganizedLinks,
      });
    }

    return grouped;
  }

  private extractUrlAndTitleFromInput(rawInput: string): ParsedLinkInput {
    const value = rawInput.trim();
    if (value.length === 0) {
      return { url: '', title: '' };
    }

    const urlPattern: RegExp = /https?:\/\/[^\s]+/i;
    const hostPattern: RegExp = /([a-z0-9-]+\.)+[a-z]{2,}([/?#][^\s]*)?/i;
    const trailingNoisePattern: RegExp = /["'\]\[\)\(\}\{>,.;!?]+$/;
    const matchedUrl = value.match(urlPattern);

    if (matchedUrl && matchedUrl.length > 0) {
      const url = matchedUrl[0].replace(trailingNoisePattern, '');
      const titleCandidate = value.replace(matchedUrl[0], '').trim().replace(/\s+/g, ' ');
      return {
        url,
        title: titleCandidate.length > 200 ? titleCandidate.slice(0, 200) : titleCandidate,
      };
    }

    const matchedHost = value.match(hostPattern);
    if (matchedHost && matchedHost.length > 0) {
      const rawHost = matchedHost[0].replace(trailingNoisePattern, '');
      const titleCandidate = value.replace(matchedHost[0], '').trim().replace(/\s+/g, ' ');
      return {
        url: `https://${rawHost}`,
        title: titleCandidate.length > 200 ? titleCandidate.slice(0, 200) : titleCandidate,
      };
    }

    return { url: '', title: '' };
  }

  private tabActiveColor(): string {
    return this.themePalette().accentStrong;
  }

  private tabActiveTextColor(): string {
    return '#ffffff';
  }

  private surfaceColor(): string {
    return this.themePalette().surface;
  }

  private pageColor(): string {
    return this.themePalette().page;
  }

  private cardColor(): string {
    return this.themePalette().card;
  }

  private selectedCardColor(): string {
    return this.themePalette().cardSelected;
  }

  private newlyAddedCardColor(): string {
    return this.themePalette().cardSuccess;
  }

  private primaryTextColor(): string {
    return this.themePalette().textPrimary;
  }

  private secondaryTextColor(): string {
    return this.themePalette().textSecondary;
  }

  private accentColor(): string {
    return this.themePalette().accent;
  }

  private dangerColor(): string {
    return this.themePalette().danger;
  }

  private panelBorderColor(): string {
    return this.themePalette().border;
  }

  private inputBackgroundColor(): string {
    return this.themePalette().input;
  }

  private primaryActionBackgroundColor(): string {
    return this.isDarkTheme() ? this.tabActiveColor() : this.themePalette().accentStrong;
  }

  private primaryActionTextColor(): string {
    return '#ffffff';
  }

  private primaryActionShadowColor(): string {
    return this.isDarkTheme() ? '#30000000' : '#1f2563eb';
  }

  private fabBackgroundColor(): string {
    return this.cardColor();
  }

  private fabIconColor(): string {
    return this.accentColor();
  }

  private fabBorderColor(): string {
    return this.themePalette().border;
  }

  private secondaryActionBackgroundColor(): string {
    return this.themePalette().accentSoft;
  }

  private secondaryActionTextColor(): string {
    return this.accentColor();
  }

  private themeModeLabel(): string {
    if (this.themeMode === 'dark') {
      return 'Dark';
    }

    if (this.themeMode === 'light') {
      return 'Light';
    }

    return 'System';
  }

  private isThemeOptionSelected(mode: ThemeMode): boolean {
    return this.themeMode === mode;
  }

  private themePalette() {
    const effectiveMode: ThemeMode =
      (this.themeMode === 'system' && this.deviceDarkMode) ? 'dark' : this.themeMode;
    return createThemePalette(effectiveMode);
  }

  private isDarkTheme(): boolean {
    return this.themeMode === 'dark' || (this.themeMode === 'system' && this.deviceDarkMode);
  }

  private syncApiContext(): void {
    this.instance = normalizeInstanceUrl(this.instance);
    this.api.setInstance(this.instance);
    this.api.setToken(this.token);
    this.settingsInstance = this.instance;
  }

  onBackPress(): boolean {
    if (this.quickMenuOpen) {
      this.quickMenuOpen = false;
      return true;
    }

    if (this.activeModal !== 'none') {
      this.closeCurrentModal();
      return true;
    }

    if (shouldReturnToDashboard(this.mainView)) {
      this.mainView = 'dashboard';
      this.refreshDashboard();
      return true;
    }

    return false;
  }

  private async ensureCurrentUserId(): Promise<void> {
    if (this.currentUserId > 0) {
      return;
    }

    this.syncApiContext();
    this.currentUserId = await this.api.fetchCurrentUserId();
  }

  private async restoreSession(): Promise<void> {
    const fallback = createDefaultSessionState();

    try {
      if (this.storage === null) {
        this.storage = new SessionStorage(getContext(this));
      }

      const state = await this.storage.load();
      this.instance = normalizeInstanceUrl(state.instance);
      this.settingsInstance = this.instance;
      this.token = state.token;
      this.currentUserId = 0;
      this.themeMode = normalizeThemeMode(state.theme);
      this.syncApiContext();

      if (this.token.length > 0) {
        await this.ensureCurrentUserId();
        await Promise.all([this.refreshLinks(true), this.refreshDashboard()]);
        await this.consumeSharedUrlAndMaybeSave();

        if (this.notice.length === 0) {
          this.setNotice('Session restored.', false);
        }
      }
    } catch (error) {
      this.instance = fallback.instance;
      this.settingsInstance = fallback.instance;
      this.token = fallback.token;
      this.currentUserId = 0;
      this.themeMode = fallback.theme;
      this.setNotice(`Restore failed: ${this.formatError(error)}`, true);
    } finally {
      this.restoring = false;
    }
  }

  private async persistSessionState(): Promise<void> {
    if (this.storage === null) {
      this.storage = new SessionStorage(getContext(this));
    }

    await this.storage.save({
      instance: normalizeInstanceUrl(this.instance),
      token: this.token,
      theme: this.themeMode,
    });
  }

  private applySelectedLink(link: LinkItem): void {
    this.selectedLink = link;
    this.editName = link.name;
    this.editUrl = link.url;
    this.editDescription = link.description;
    this.editPinned = link.pinned;
    this.editCollectionQuery = link.collectionName;
    this.editTagsInput = link.tags.map((tag) => tag.name).join(', ');
    this.editTagPickerQuery = '';
  }

  private clearSelectedLink(): void {
    this.selectedLink = emptyLinkItem();
    this.editName = '';
    this.editUrl = '';
    this.editDescription = '';
    this.editPinned = false;
    this.editCollectionQuery = '';
    this.editTagsInput = '';
    this.editTagPickerQuery = '';
    this.detailLoading = false;
    this.detailSaving = false;
    this.detailDeleting = false;
    this.pinSaving = false;
  }

  private markLinkAsRecentlyAdded(linkId: number): void {
    this.highlightedLinkId = linkId > 0 ? linkId : 0;
  }

  private replaceLinkInList(link: LinkItem): void {
    this.links = this.links.map((item: LinkItem) => {
      if (item.id === link.id) {
        return link;
      }

      return item;
    });
    this.homePreviewLinks = this.homePreviewLinks.map((item: LinkItem) => item.id === link.id ? link : item);
    this.dashboardLinks = this.dashboardLinks.map((item: LinkItem) => item.id === link.id ? link : item);
    this.pinnedLinks = this.pinnedLinks.map((item: LinkItem) => item.id === link.id ? link : item);
    if (link.pinned) {
      const exists = this.pinnedLinks.some((item: LinkItem) => item.id === link.id);
      if (!exists) {
        this.pinnedLinks = [link].concat(this.pinnedLinks);
      }
    } else {
      this.pinnedLinks = this.pinnedLinks.filter((item: LinkItem) => item.id !== link.id);
    }
  }

  private removeLinkFromList(linkId: number): void {
    this.links = this.links.filter((item: LinkItem) => item.id !== linkId);
    this.homePreviewLinks = this.homePreviewLinks.filter((item: LinkItem) => item.id !== linkId);
  }

  private async handleSaveSettings(): Promise<void> {
    const previousInstance = this.instance;
    const nextInstance = normalizeInstanceUrl(this.settingsInstance);
    const changedServer = previousInstance !== nextInstance;

    this.instance = nextInstance;
    this.syncApiContext();

    if (changedServer) {
      this.token = '';
      this.currentUserId = 0;
      this.links = [];
      this.dashboardLinks = [];
      this.pinnedLinks = [];
      this.homePreviewLinks = [];
      this.collections = [];
      this.knownTagNames = [];
      this.allTags = [];
      this.pinnedTotal = -1;
      this.tagsTotal = -1;
      this.linksTotal = -1;
      this.nextCursor = 0;
      this.hasMore = true;
      this.selectedCollectionFilterId = 0;
      this.showPinnedOnly = false;
      this.clearSelectedLink();
      this.activeModal = 'none';
      this.resetCollectionDraft();
      this.clearNewLinkDraft();
      this.username = '';
      this.password = '';
      this.syncApiContext();
      this.setNotice('Settings saved. Server changed, please sign in again.', false);
    } else {
      this.setNotice('Settings saved.', false);
    }

    try {
      await this.persistSessionState();
      this.mainView = 'settings';
    } catch (error) {
      this.setNotice(`Save settings failed: ${this.formatError(error)}`, true);
    }
  }

  private async handleSignIn(): Promise<void> {
    if (this.loading) {
      return;
    }

    this.loading = true;
    this.setNotice('', false);

    try {
      this.syncApiContext();
      const token = await this.api.signIn(this.username.trim(), this.password);
      this.token = token;
      this.syncApiContext();
      this.currentUserId = await this.api.fetchCurrentUserId();
      await this.persistSessionState();
      await Promise.all([this.refreshLinks(true), this.refreshDashboard()]);
      await this.consumeSharedUrlAndMaybeSave();
      this.setNotice('Signed in successfully.', false);
    } catch (error) {
      this.setNotice(`Sign in failed: ${this.formatError(error)}`, true);
    } finally {
      this.loading = false;
    }
  }

  private async handleAddLink(): Promise<void> {
    const parsedInput = this.extractUrlAndTitleFromInput(this.newLinkUrl);
    if (parsedInput.url.length === 0) {
      this.setNotice('Please enter a URL.', true);
      return;
    }

    const matchedCollection = this.matchedDraftCollection();
    if (this.newLinkCollectionQuery.trim().length > 0 && matchedCollection === null) {
      this.setNotice('Collection not found. Use an existing collection name.', true);
      return;
    }

    const normalizedUrl = /^https?:\/\//i.test(parsedInput.url)
      ? parsedInput.url
      : `https://${parsedInput.url}`;

    this.loading = true;
    this.setNotice('', false);

    try {
      this.syncApiContext();
      this.selectedCollectionFilterId = 0;
      this.showPinnedOnly = false;
      this.searchQuery = '';
      const title = this.newLinkTitle.trim().length > 0 ? this.newLinkTitle.trim() : parsedInput.title;
      const createdLink = await this.api.addLink(normalizedUrl, title, {
        tagNames: this.resolvedDraftTags(),
        collection: matchedCollection,
      });
      this.clearNewLinkDraft();
      await this.refreshLinks(true);
      await this.refreshDashboard();
      this.markLinkAsRecentlyAdded(createdLink.id);
      this.mainView = 'elements';
      this.elementsView = 'links';
      this.activeModal = 'none';
      this.setNotice('Link added.', false);
    } catch (error) {
      this.setNotice(`Add link failed: ${this.formatError(error)}`, true);
    } finally {
      this.loading = false;
    }
  }

  private async handleSelectLink(linkId: number): Promise<void> {
    this.activeModal = 'edit';
    this.detailLoading = true;
    this.setNotice('', false);

    try {
      this.syncApiContext();
      const link = await this.api.getLink(linkId);
      this.applySelectedLink(link);
    } catch (error) {
      this.setNotice(`Load detail failed: ${this.formatError(error)}`, true);
    } finally {
      this.detailLoading = false;
    }
  }

  private async handleSaveLink(): Promise<void> {
    if (this.selectedLink.id === 0 || this.detailSaving) {
      return;
    }

    const rawUrl = this.editUrl.trim();
    if (rawUrl.length === 0) {
      this.setNotice('URL cannot be empty.', true);
      return;
    }

    const normalizedUrl = /^https?:\/\//i.test(rawUrl) ? rawUrl : `https://${rawUrl}`;
    const matchedCollection = this.matchedEditCollection();
    if (this.editCollectionQuery.trim().length > 0 && matchedCollection === null) {
      this.setNotice('Collection not found. Use an existing collection name.', true);
      return;
    }

    const nextCollectionId = matchedCollection !== null ? matchedCollection.id : this.selectedLink.collectionId;
    const nextCollectionOwnerId = matchedCollection !== null ? matchedCollection.ownerId : this.selectedLink.collectionOwnerId;
    const nextCollectionName = matchedCollection !== null ? matchedCollection.name : this.selectedLink.collectionName;
    const nextCollectionColor = matchedCollection !== null ? matchedCollection.color : this.selectedLink.collectionColor;
    const nextTags: Array<LinkTag> = this.resolvedEditTags().map((name: string, index: number) => {
      const tag: LinkTag = {
        id: -(index + 1),
        name,
      };
      return tag;
    });
    const nextLink: LinkItem = {
      id: this.selectedLink.id,
      name: this.editName.trim(),
      url: normalizedUrl,
      description: this.editDescription.trim(),
      createdAt: this.selectedLink.createdAt,
      collectionId: nextCollectionId,
      collectionOwnerId: nextCollectionOwnerId,
      collectionName: nextCollectionName,
      collectionColor: nextCollectionColor,
      pinned: this.selectedLink.pinned,
      tags: nextTags,
    };

    this.detailSaving = true;
    this.setNotice('', false);

    try {
      this.syncApiContext();
      const savedLink = await this.api.updateLink(nextLink);
      this.applySelectedLink(savedLink);
      this.replaceLinkInList(savedLink);
      await this.refreshDashboard();
      this.activeModal = 'none';
      this.setNotice('Link updated.', false);
    } catch (error) {
      this.setNotice(`Save failed: ${this.formatError(error)}`, true);
    } finally {
      this.detailSaving = false;
    }
  }

  private async handleDeleteLink(): Promise<void> {
    if (this.selectedLink.id === 0 || this.detailDeleting) {
      return;
    }

    this.detailDeleting = true;
    this.setNotice('', false);

    try {
      this.syncApiContext();
      const deletingId = this.selectedLink.id;
      await this.api.deleteLink(deletingId);
      this.removeLinkFromList(deletingId);
      this.clearSelectedLink();
      this.activeModal = 'none';
      await this.refreshDashboard();
      this.setNotice('Link deleted.', false);
    } catch (error) {
      this.setNotice(`Delete failed: ${this.formatError(error)}`, true);
    } finally {
      this.detailDeleting = false;
    }
  }

  private async deleteLinkById(linkId: number): Promise<void> {
    if (linkId <= 0 || this.detailDeleting) {
      return;
    }

    this.detailDeleting = true;
    this.setNotice('', false);

    try {
      this.syncApiContext();
      await this.api.deleteLink(linkId);
      this.removeLinkFromList(linkId);
      this.dashboardLinks = this.dashboardLinks.filter((item: LinkItem) => item.id !== linkId);
      this.pinnedLinks = this.pinnedLinks.filter((item: LinkItem) => item.id !== linkId);
      if (this.selectedLink.id === linkId) {
        this.clearSelectedLink();
        this.activeModal = 'none';
      }
      await this.refreshDashboard();
      this.setNotice('Link deleted.', false);
    } catch (error) {
      this.setNotice(`Delete failed: ${this.formatError(error)}`, true);
    } finally {
      this.detailDeleting = false;
    }
  }

  private handleLinkLongPress(item: LinkItem): void {
    this.handleSelectLink(item.id);
    this.setNotice('Editing link.', false);
  }

  private async handleTogglePin(): Promise<void> {
    if (this.selectedLink.id === 0 || this.pinSaving) {
      return;
    }

    this.pinSaving = true;
    this.setNotice('', false);

    try {
      await this.ensureCurrentUserId();
      this.syncApiContext();
      const savedLink = await this.api.setPinned(this.selectedLink, !this.editPinned, this.currentUserId);
      this.applySelectedLink(savedLink);
      this.replaceLinkInList(savedLink);
      await this.refreshDashboard();
      this.setNotice(savedLink.pinned ? 'Pinned to dashboard.' : 'Removed from dashboard.', false);
    } catch (error) {
      this.setNotice(`Pin update failed: ${this.formatError(error)}`, true);
    } finally {
      this.pinSaving = false;
    }
  }

  private async handleCreateCollection(): Promise<void> {
    const collectionName = this.newCollectionName.trim();
    if (collectionName.length === 0) {
      this.setNotice('Collection name cannot be empty.', true);
      return;
    }

    const matchedParent = this.matchedParentCollection();
    if (this.newCollectionParentQuery.trim().length > 0 && matchedParent === null) {
      this.setNotice('Parent collection not found. Use an existing collection name.', true);
      return;
    }

    this.collectionSaving = true;
    this.setNotice('', false);

    try {
      this.syncApiContext();
      const createdCollection = await this.api.createCollection(collectionName, {
        description: this.newCollectionDescription,
        color: this.newCollectionColor,
        parentId: matchedParent !== null ? matchedParent.id : undefined,
      });
      await this.refreshDashboard();
      if (this.collectionModalSource === 'add') {
        this.newLinkCollectionQuery = createdCollection.name;
      } else {
        this.editCollectionQuery = createdCollection.name;
      }
      this.activeModal = this.collectionModalReturn;
      this.setNotice('Collection created.', false);
    } catch (error) {
      this.setNotice(`Create collection failed: ${this.formatError(error)}`, true);
    } finally {
      this.collectionSaving = false;
    }
  }

  private async handleSignOut(): Promise<void> {
    this.token = '';
    this.currentUserId = 0;
    this.links = [];
    this.dashboardLinks = [];
    this.pinnedLinks = [];
    this.homePreviewLinks = [];
    this.collections = [];
    this.knownTagNames = [];
    this.allTags = [];
    this.pinnedTotal = -1;
    this.tagsTotal = -1;
    this.linksTotal = -1;
    this.nextCursor = 0;
    this.hasMore = true;
    this.selectedCollectionFilterId = 0;
    this.showPinnedOnly = false;
    this.password = '';
    this.activeModal = 'none';
    this.resetCollectionDraft();
    this.clearNewLinkDraft();
    this.clearSelectedLink();
    this.syncApiContext();

    try {
      await this.persistSessionState();
    } catch (error) {
      this.setNotice(`Sign out storage update failed: ${this.formatError(error)}`, true);
      return;
    }

    this.setNotice('Signed out.', false);
  }


  private async handleDashboardPullRefresh(): Promise<void> {
    this.dashboardRefreshing = true;
    try {
      await Promise.all([
        this.refreshDashboard(),
        this.refreshLinks(true),
      ]);
    } finally {
      this.dashboardRefreshing = false;
    }
  }

  private async refreshLinks(reset: boolean): Promise<void> {
    if (this.token.length === 0) {
      return;
    }

    if (reset) {
      this.loading = true;
      this.nextCursor = 0;
      this.hasMore = true;
    } else {
      if (!this.hasMore || this.loadingMore) {
        return;
      }
      this.loadingMore = true;
    }

    try {
      this.syncApiContext();
      const page = await this.api.fetchLinks(
        reset ? 0 : this.nextCursor,
        this.searchQuery,
        this.selectedCollectionFilterId,
        this.showPinnedOnly
      );

      if (reset) {
        this.links = page.links;
      } else {
        this.links = this.links.concat(page.links);
      }
      this.mergeTagsFromLinks(page.links);

      this.nextCursor = page.nextCursor;
      this.hasMore = page.nextCursor >= 0;
    } catch (error) {
      if (reset && this.isAuthFailure(error)) {
        this.token = '';
        await this.persistSessionState();
      }
      this.setNotice(`Fetch links failed: ${this.formatError(error)}`, true);
    } finally {
      if (reset) {
        this.loading = false;
      }
      this.loadingMore = false;
    }
  }

  private async refreshDashboard(): Promise<void> {
    if (this.token.length === 0) {
      return;
    }

    this.dashboardLoading = true;
    try {
      this.syncApiContext();
      const result = await Promise.all([
        this.api.fetchDashboardLinks(),
        this.api.fetchPinnedLinks(),
        this.api.fetchCollections(),
        this.api.fetchLinks(0, '', 0, false),
        this.fetchTagsOrEmpty(),
        this.fetchDashboardTotalsOrNull(),
      ]);
      this.dashboardLinks = result[0];
      this.pinnedLinks = result[1];
      this.collections = result[2];
      this.homePreviewLinks = result[3].links;
      this.allTags = result[4];
      const totals: DashboardTotals | null = result[5];
      this.pinnedTotal = totals !== null ? totals.numberOfPinnedLinks : result[1].length;
      this.tagsTotal = totals !== null && totals.numberOfTags !== null
        ? totals.numberOfTags
        : result[4].length;
      this.linksTotal = result[2].reduce((sum: number, c: CollectionItem) => sum + c.linkCount, 0);
      this.mergeTagNamesFromTags(result[4]);
    } catch (error) {
      this.setNotice(`Fetch dashboard failed: ${this.formatError(error)}`, true);
    } finally {
      this.dashboardLoading = false;
    }
  }

  private async fetchTagsOrEmpty(): Promise<Array<LinkTag>> {
    try {
      return await this.api.fetchTags();
    } catch (error) {
      console.info(`Index fetchTags failed: ${this.formatError(error)}`);
      return [];
    }
  }

  private async fetchDashboardTotalsOrNull(): Promise<DashboardTotals | null> {
    try {
      return await this.api.fetchDashboardTotals();
    } catch (error) {
      console.info(`Index fetchDashboardTotals failed: ${this.formatError(error)}`);
      return null;
    }
  }

  private openLinkInBrowser(rawUrl: string): void {
    const normalizedUrl = /^https?:\/\//i.test(rawUrl.trim()) ? rawUrl.trim() : `https://${rawUrl.trim()}`;
    if (normalizedUrl.length === 0) {
      this.setNotice('Invalid URL.', true);
      return;
    }

    const context = getContext(this) as common.UIAbilityContext;
    context.startAbility({
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: normalizedUrl,
      type: 'text/html',
    }).catch((error: Error) => {
      this.setNotice(`Open URL failed: ${this.formatError(error)}`, true);
    });
  }

  private isAuthFailure(error: Object): boolean {
    const message = this.formatError(error);
    return message.indexOf('HTTP_401') >= 0 || message.indexOf('HTTP_403') >= 0;
  }

  private setNotice(value: string, isError: boolean): void {
    this.notice = value;
    this.noticeIsError = isError;

    if (this.noticeTimer >= 0) {
      clearTimeout(this.noticeTimer);
      this.noticeTimer = -1;
    }

    if (value.length > 0) {
      this.noticeTimer = setTimeout(() => {
        this.notice = '';
        this.noticeTimer = -1;
      }, isError ? 2600 : 1800);
    }
  }

  private formatDateLabel(value: string): string {
    try {
      return new Date(value).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
      });
    } catch (error) {
      return value;
    }
  }

  private formatError(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }

    return `${error}`;
  }

  private startSharePolling(): void {
    if (this.sharePollTimer >= 0) {
      return;
    }

    this.sharePollTimer = setInterval(() => {
      if (this.restoring) {
        return;
      }

      this.consumeSharedUrlAndMaybeSave().catch((error: Object) => {
        this.setNotice(`Share polling failed: ${this.formatError(error)}`, true);
      });
    }, 1200);
    console.info('Index share poll started');
  }

  private async consumeSharedUrlAndMaybeSave(): Promise<void> {
    const sharedIntent = consumePendingSharedIntent();
    const sharedUrl = sharedIntent.url;
    const sharedTitle = sharedIntent.title;
    if (sharedUrl.length === 0) {
      return;
    }
    console.info(`Index consumeSharedUrlAndMaybeSave got sharedUrl=${sharedUrl}, sharedTitle=${sharedTitle}`);

    this.applyNewLinkDraft(sharedUrl, sharedTitle);

    if (this.token.length === 0) {
      console.info('Index shared url captured but no token');
      this.setNotice('Shared URL captured. Sign in to save it.', false);
      return;
    }

    this.openAddModal();
    this.setNotice('Shared URL captured. You can set collection and tags before saving.', false);
  }
}
