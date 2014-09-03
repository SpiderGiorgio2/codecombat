CocoView = require 'views/kinds/CocoView'
AddThangsView = require './AddThangsView'
thangs_template = require 'templates/editor/level/thangs-tab-view'
Level = require 'models/Level'
ThangType = require 'models/ThangType'
LevelComponent = require 'models/LevelComponent'
CocoCollection = require 'collections/CocoCollection'
{isObjectID} = require 'models/CocoModel'
Surface = require 'lib/surface/Surface'
Thang = require 'lib/world/thang'
LevelThangEditView = require './LevelThangEditView'
ComponentsCollection = require 'collections/ComponentsCollection'

# Moving the screen while dragging thangs constants
MOVE_MARGIN = 0.15
MOVE_SPEED = 13

# Let us place these on top of other Thangs
overlappableThangTypeNames = ['Torch', 'Chains', 'Bird', 'Cloud 1', 'Cloud 2', 'Cloud 3', 'Waterfall', 'Obstacle']

class ThangTypeSearchCollection extends CocoCollection
  url: '/db/thang.type?project=original,name,version,slug,kind,components'
  model: ThangType

module.exports = class ThangsTabView extends CocoView
  id: 'thangs-tab-view'
  className: 'tab-pane active'
  template: thangs_template

  subscriptions:
    'surface:sprite-selected': 'onExtantThangSelected'
    'surface:mouse-moved': 'onSurfaceMouseMoved'
    'surface:mouse-over': 'onSurfaceMouseOver'
    'surface:mouse-out': 'onSurfaceMouseOut'
    'editor:edit-level-thang': 'editThang'
    'editor:level-thang-edited': 'onLevelThangEdited'
    'editor:level-thang-done-editing': 'onLevelThangDoneEditing'
    'editor:view-switched': 'onViewSwitched'
    'sprite:dragged': 'onSpriteDragged'
    'sprite:mouse-up': 'onSpriteMouseUp'
    'sprite:mouse-down': 'onSpriteMouseDown'
    'sprite:double-clicked': 'onSpriteDoubleClicked'
    'surface:stage-mouse-up': 'onStageMouseUp'
    'editor:random-terrain-generated': 'onRandomTerrainGenerated'

  events:
    'click #extant-thangs-filter button': 'onFilterExtantThangs'
    'click #delete': 'onDeleteClicked'
    'click #duplicate': 'onDuplicateClicked'
    'click #thangs-container-toggle': 'toggleThangsContainer'
    'click #thangs-palette-toggle': 'toggleThangsPalette'
#    'click .add-thang-palette-icon': 'toggleThangsPalette'

  shortcuts:
    'esc': 'selectAddThang'
    'delete, del, backspace': 'deleteSelectedExtantThang'
    'left': -> @moveAddThangSelection -1
    'right': -> @moveAddThangSelection 1
    'ctrl+z, ⌘+z': 'undo'
    'ctrl+shift+z, ⌘+shift+z': 'redo'

  constructor: (options) ->
    super options
    @world = options.world

    # should load depended-on Components, too
    @thangTypes = @supermodel.loadCollection(new ThangTypeSearchCollection(), 'thangs').model
    # just loading all Components for now: https://github.com/codecombat/codecombat/issues/405
    @componentCollection = @supermodel.loadCollection(new ComponentsCollection(), 'components').load()
    @level = options.level

    $(document).bind 'contextmenu', @preventDefaultContextMenu

  getRenderData: (context={}) ->
    context = super(context)
    return context unless @supermodel.finished()
    thangTypes = (thangType.attributes for thangType in @supermodel.getModels(ThangType))
    thangTypes = _.uniq thangTypes, false, 'original'
    thangTypes = _.reject thangTypes, kind: 'Mark'
    groupMap = {}
    for thangType in thangTypes
      groupMap[thangType.kind] ?= []
      groupMap[thangType.kind].push thangType

    groups = []
    for groupName in Object.keys(groupMap).sort()
      someThangTypes = groupMap[groupName]
      someThangTypes = _.sortBy someThangTypes, 'name'
      group =
        name: groupName
        thangs: someThangTypes
      groups.push group

    context.thangTypes = thangTypes
    context.groups = groups
    context

  undo: (e) ->
    if not @editThangView then @thangsTreema.undo() else @editThangView.undo()

  redo: (e) ->
    if not @editThangView then @thangsTreema.redo() else @editThangView.redo()

  afterRender: ->
    super()
    return unless @supermodel.finished()
    $('.tab-content').mousedown @selectAddThang
    $('#thangs-list').bind 'mousewheel', @preventBodyScrollingInThangList
    @$el.find('#extant-thangs-filter button:first').button('toggle')
    $(window).on 'resize', @onWindowResize
    @addThangsView = @insertSubView new AddThangsView world: @world
    @buildInterface() # refactor to not have this trigger when this view re-renders?
    if @thangsTreema.data.length
      @$el.find('#canvas-overlay').css('display', 'none')

  onFilterExtantThangs: (e) ->
    @$el.find('#extant-thangs-filter button.active').button('toggle')
    button = $(e.target).closest('button')
    button.button('toggle')
    val = button.val()
    @thangsTreema.$el.removeClass(@lastHideClass) if @lastHideClass
    @thangsTreema.$el.addClass(@lastHideClass = "hide-except-#{val}") if val

  preventBodyScrollingInThangList: (e) ->
    @scrollTop += (if e.deltaY < 0 then 1 else -1) * 30
    e.preventDefault()

  buildInterface: (e) ->
    @level = e.level if e

    data = $.extend(true, {}, @level.attributes)
    treemaOptions =
      schema: Level.schema.properties.thangs
      data: data.thangs
      supermodel: @supermodel
      callbacks:
        change: @onThangsChanged
        select: @onTreemaThangSelected
        dblclick: @onTreemaThangDoubleClicked
      readOnly: true
      nodeClasses:
        thang: ThangNode
        array: ThangsNode
      world: @world

    @thangsTreema = @$el.find('#thangs-treema').treema treemaOptions
    @thangsTreema.build()
    @thangsTreema.open()
    @onThangsChanged()  # Initialize the World with Thangs
    @initSurface()
    thangsHeaderHeight = $('#thangs-header').height()
    oldHeight = $('#thangs-list').height()
    $('#thangs-list').height(oldHeight - thangsHeaderHeight)
    if data.thangs?.length
      @$el.find('.generate-terrain-button').hide()

  initSurface: ->
    surfaceCanvas = $('canvas#surface', @$el)
    @surface = new Surface @world, surfaceCanvas, {
      wizards: false
      paths: false
      grid: true
      navigateToSelection: false
      thangTypes: @supermodel.getModels(ThangType)
      showInvisible: true
      frameRate: 15
    }
    @surface.playing = false
    @surface.setWorld @world
    @centerCamera()

  centerCamera: ->
    [width, height] = @world.size()
    width = Math.max width, 80
    height = Math.max height, 68
    {left, top, right, bottom} = @world.getBounds()
    center = x: left + width / 2, y: bottom + height / 2
    sup = @surface.camera.worldToSurface center
    zoom = 0.94 * 92.4 / width  # Zoom 1.0 lets us see 92.4 meters.
    @surface.camera.zoomTo(sup, zoom, 0)

  destroy: ->
    @selectAddThangType null
    @surface.destroy()
    $(window).off 'resize', @onWindowResize
    $(document).unbind 'contextmenu', @preventDefaultContextMenu
    @thangsTreema?.destroy()
    super()

  onViewSwitched: (e) ->
    @selectAddThang null, true
    @surface?.spriteBoss?.selectSprite null, null

  onSpriteMouseDown: (e) ->
    @dragged = false
    # Sprite clicks happen after stage clicks, but we need to know whether a sprite is being clicked.
    # clearTimeout @backgroundAddClickTimeout
    # if e.originalEvent.nativeEvent.button == 2
    #   @onSpriteContextMenu e

  onStageMouseUp: (e) ->
    if @addThangSprite
      @surface.camera.lock()
      # If we click on the background, we need to add @addThangSprite, but not if onSpriteMouseUp will fire.
      @backgroundAddClickTimeout = _.defer => @onExtantThangSelected {}
    $('#contextmenu').hide()

  onSpriteDragged: (e) ->
    return unless @selectedExtantThang and e.thang?.id is @selectedExtantThang?.id
    @dragged = true
    @surface.camera.dragDisabled = true
    {stageX, stageY} = e.originalEvent
    wop = @surface.camera.screenToWorld x: stageX, y: stageY
    wop.z = @selectedExtantThang.depth / 2
    @adjustThangPos @selectedExtantSprite, @selectedExtantThang, wop
    [w, h] = [@surface.camera.canvasWidth, @surface.camera.canvasHeight]
    @calculateMovement(stageX / w, stageY / h, w / h)

  onSpriteMouseUp: (e) ->
    clearTimeout @backgroundAddClickTimeout
    @surface.camera.unlock()
    if e.originalEvent.nativeEvent.button == 2 and @selectedExtantThang
      @onSpriteContextMenu e
    clearInterval(@movementInterval) if @movementInterval?
    @movementInterval = null
    @surface.camera.dragDisabled = false
    return unless @selectedExtantThang and e.thang?.id is @selectedExtantThang?.id
    pos = @selectedExtantThang.pos
    path = "id=#{@selectedExtantThang.id}/components/original=#{LevelComponent.PhysicalID}"
    physical = @thangsTreema.get path
    return if not physical or (physical.config.pos.x is pos.x and physical.config.pos.y is pos.y)
    @thangsTreema.set path + '/config/pos', x: pos.x, y: pos.y, z: pos.z

  onSpriteDoubleClicked: (e) ->
    return unless e.thang and not @dragged
    @editThang thangID: e.thang.id

  onRandomTerrainGenerated: (e) ->
    @thangsBatch = []
    nonRandomThangs = (thang for thang in @thangsTreema.get('') when not /Random/.test thang.id)
    @thangsTreema.set '', nonRandomThangs
    for thang in e.thangs
      @selectAddThangType thang.id
      @addThang @addThangType, thang.pos, true
    @batchInsert()
    @selectAddThangType null


  # TODO: figure out a good way to have all Surface clicks and Treema clicks just proxy in one direction, so we can maintain only one way of handling selection and deletion
  onExtantThangSelected: (e) ->
    @selectedExtantSprite?.setNameLabel? null unless @selectedExtantSprite is e.sprite
    @selectedExtantThang = e.thang
    @selectedExtantSprite = e.sprite
    if e.thang and (key.alt or key.meta)
      # We alt-clicked, so create a clone addThang
      @selectAddThangType e.thang.spriteName, @selectedExtantThang
    else if @justAdded()
      # Skip double insert due to extra selection event
      null
    else if e.thang and not (@addThangSprite and @addThangType.get('name') in overlappableThangTypeNames)
      # We clicked on a Thang (or its Treema), so select the Thang
      @selectAddThang null, true
      @selectedExtantThangClickTime = new Date()
      treemaThang = _.find @thangsTreema.childrenTreemas, (treema) => treema.data.id is @selectedExtantThang.id
      if treemaThang
        # Show the label above selected thang, notice that we may get here from thang-edit-view, so it will be selected but no label
        # also covers selecting from Treema
        @selectedExtantSprite.setNameLabel @selectedExtantSprite.thangType.get('name') + ': ' + @selectedExtantThang.id
        if not treemaThang.isSelected()
          treemaThang.select()
          @thangsTreema.$el.scrollTop(@thangsTreema.$el.find('.treema-children .treema-selected')[0].offsetTop)
    else if @addThangSprite
      # We clicked on the background when we had an add Thang selected, so add it
      @addThang @addThangType, @addThangSprite.thang.pos
      @lastAddTime = new Date()

  justAdded: -> @lastAddTime and (new Date() - @lastAddTime) < 150

  selectAddThang: (e, forceDeselect=false) =>
    return if e? and $(e.target).closest('#thang-search').length # Ignore if you're trying to search thangs
    return unless (e? and $(e.target).closest('#thangs-tab-view').length) or key.isPressed('esc') or forceDeselect
    if e then target = $(e.target) else target = @$el.find('.add-thangs-palette')  # pretend to click on background if no event
    return true if target.attr('id') is 'surface'
    target = target.closest('.add-thang-palette-icon')
    wasSelected = target.hasClass 'selected'
    @$el.find('.add-thangs-palette .add-thang-palette-icon.selected').removeClass('selected')
    @selectAddThangType(if wasSelected then null else target.attr 'data-thang-type') unless key.alt or key.meta
    target.addClass('selected') if @addThangType
    #false # was causing #1099, any reason to keep?

  moveAddThangSelection: (direction) ->
    return unless @addThangType
    icons = $('.add-thangs-palette .add-thang-palette-icon')
    selectedIcon = icons.filter('.selected')
    selectedIndex = icons.index selectedIcon
    nextSelectedIndex = (selectedIndex + direction + icons.length) % icons.length
    @selectAddThang {target: icons[nextSelectedIndex]}

  selectAddThangType: (type, @cloneSourceThang) ->
    if _.isString type
      type = _.find @supermodel.getModels(ThangType), (m) -> m.get('name') is type
    pos = @addThangSprite?.thang.pos  # Maintain old sprite's pos if we have it
    @surface.spriteBoss.removeSprite @addThangSprite if @addThangSprite
    @addThangType = type
    if @addThangType
      thang = @createAddThang()
      @addThangSprite = @surface.spriteBoss.addThangToSprites thang, @surface.spriteBoss.spriteLayers['Floating']
      @addThangSprite.notOfThisWorld = true
      @addThangSprite.imageObject.alpha = 0.75
      @addThangSprite.playSound? 'selected'
      pos ?= x: Math.round(@world.width / 2), y: Math.round(@world.height / 2)
      @adjustThangPos @addThangSprite, thang, pos
    else
      @addThangSprite = null

  createEssentialComponents: (defaultComponents) ->
    physicalConfig = {pos: {x: 10, y: 10, z: 1}}
    if physicalOriginal = _.find(defaultComponents ? [], original: LevelComponent.PhysicalID)
      physicalConfig.pos.z = physicalOriginal.config?.pos?.z ? 1  # Get the z right
    [
      {original: LevelComponent.ExistsID, majorVersion: 0, config: {}}
      {original: LevelComponent.PhysicalID, majorVersion: 0, config: physicalConfig}
    ]

  createAddThang: ->
    allComponents = (lc.attributes for lc in @supermodel.getModels LevelComponent)
    rawComponents = @addThangType.get('components') ? []
    rawComponents = @createEssentialComponents() unless rawComponents.length
    mockThang = {components: rawComponents}
    @level.sortThangComponents [mockThang], allComponents
    components = []
    for raw in mockThang.components
      comp = _.find allComponents, {original: raw.original}
      continue if comp.name in ['Selectable', 'Attackable']  # Don't draw health bars or intercept clicks
      componentClass = @world.loadClassFromCode comp.js, comp.name, 'component'
      components.push [componentClass, raw.config]
    thang = new Thang @world, @addThangType.get('name'), 'Add Thang Phantom'
    thang.addComponents components...
    thang

  adjustThangPos: (sprite, thang, pos) ->
    snap = sprite?.data?.snap or sprite?.thangType?.get('snap') or {x: 0.01, y: 0.01}  # Centimeter resolution by default
    pos.x = Math.round((pos.x - (thang.width ? 1) / 2) / snap.x) * snap.x + (thang.width ? 1) / 2
    pos.y = Math.round((pos.y - (thang.height ? 1) / 2) / snap.y) * snap.y + (thang.height ? 1) / 2
    pos.z = thang.depth / 2
    thang.pos = pos
    @surface.spriteBoss.update true  # Make sure Obstacle layer resets cache

  onSurfaceMouseMoved: (e) ->
    return unless @addThangSprite
    wop = @surface.camera.screenToWorld x: e.x, y: e.y
    wop.z = 0.5
    @adjustThangPos @addThangSprite, @addThangSprite.thang, wop
    null

  onSurfaceMouseOver: (e) ->
    return unless @addThangSprite
    @addThangSprite.imageObject.visible = true

  onSurfaceMouseOut: (e) ->
    return unless @addThangSprite
    @addThangSprite.imageObject.visible = false

  calculateMovement: (pctX, pctY, widthHeightRatio) ->
    MOVE_TOP_MARGIN = 1.0 - MOVE_MARGIN
    if MOVE_TOP_MARGIN > pctX > MOVE_MARGIN and MOVE_TOP_MARGIN > pctY > MOVE_MARGIN
      clearInterval(@movementInterval) if @movementInterval?
      @movementInterval = null
      return @moveLatitude = @moveLongitude = @speed = 0

    # calculating speed to be 0.0 to 1.0 within the movement buffer on the outer edge
    diff = (MOVE_MARGIN * 2) # comments are assuming MOVE_MARGIN is 0.1
    @speed = Math.max(Math.abs(pctX-0.5), Math.abs(pctY-0.5)) * 2 # pct is now 0.8 - 1.0
    @speed -= 1.0 - diff # 0.0 - 0.2
    @speed *= (1.0 / diff) # 0.0 - 1.0
    @speed *= MOVE_SPEED

    @moveLatitude = pctX * 2 - 1
    @moveLongitude = pctY * 2 - 1
    @moveLongitude /= widthHeightRatio if widthHeightRatio > 1.0
    @moveLatitude *= widthHeightRatio if widthHeightRatio < 1.0
    @movementInterval = setInterval(@moveSide, 16) unless @movementInterval?

  moveSide: =>
    return unless @speed
    c = @surface.camera
    p = {x: c.target.x + @moveLatitude * @speed / c.zoom, y: c.target.y + @moveLongitude * @speed / c.zoom}
    c.zoomTo(p, c.zoom, 0)

  deleteSelectedExtantThang: (e) =>
    return if $(e.target).hasClass 'treema-node'
    @thangsTreema.onDeletePressed e
    @onTreemaThangSelected null, @thangsTreema.getSelectedTreemas()
    Thang.resetThangIDs()  # TODO: find some way to do this when we delete from treema, too

  onThangsChanged: (e) =>
    @level.set 'thangs', @thangsTreema.data
    return if @editThangView
    serializedLevel = @level.serialize @supermodel
    try
      @world.loadFromLevel serializedLevel, false
    catch error
      console.error 'Catastrophic error loading the level:', error
    thang.isSelectable = not thang.isLand for thang in @world.thangs  # let us select walls and such
    @surface?.setWorld @world
    @selectAddThangType @addThangType, @cloneSourceThang if @addThangType  # make another addThang sprite, since the World just refreshed

    # update selection, since the thangs have been remade
    if @selectedExtantThang
      @selectedExtantSprite = @surface.spriteBoss.sprites[@selectedExtantThang.id]
      @selectedExtantThang = @selectedExtantSprite?.thang
    Backbone.Mediator.publish 'editor:thangs-edited', thangs: @world.thangs

  onTreemaThangSelected: (e, selectedTreemas) =>
    selectedThangID = _.last(selectedTreemas)?.data.id
    if selectedThangID isnt @selectedExtantThang?.id
      @surface.spriteBoss.selectThang selectedThangID, null, true

  onTreemaThangDoubleClicked: (e, treema) =>
    id = treema?.data?.id
    @editThang thangID: id if id

  batchInsert: ->
    @thangsTreema.set '', @thangsTreema.get('').concat(@thangsBatch)
    @thangsBatch = []

  addThang: (thangType, pos, batchInsert=false) ->
    @$el.find('.generate-terrain-button').hide()
    if batchInsert
      if thangType.get('name') is 'Hero Placeholder'
        thangID = 'Hero Placeholder'
        return if @level.get('type', true) isnt 'hero' or @thangsTreema.get "id=#{thangID}"
      else
        thangID = "Random #{thangType.get('name')} #{@thangsBatch.length}"
    else
      thangID = Thang.nextID(thangType.get('name'), @world) until thangID and not @thangsTreema.get "id=#{thangID}"
    if @cloneSourceThang
      components = _.cloneDeep @thangsTreema.get "id=#{@cloneSourceThang.id}/components"
    else if @level.get('type', true) is 'hero'
      components = []  # Load them all from default ThangType Components
    else
      components = _.cloneDeep thangType.get('components') ? []
    components = @createEssentialComponents(thangType.get('components')) unless components.length
    physical = _.find components, (c) -> c.config?.pos?
    physical.config.pos = x: pos.x, y: pos.y, z: physical.config.pos.z if physical
    thang = thangType: thangType.get('original'), id: thangID, components: components
    if batchInsert
      @thangsBatch.push thang
    else
      @thangsTreema.insert '', thang

  editThang: (e) ->
    if e.target  # click event
      thangData = $(e.target).data 'thang-data'
    else  # Mediator event
      window.thangsTreema = @thangsTreema
      thangData = @thangsTreema.get "id=#{e.thangID}"
    @editThangView = new LevelThangEditView thangData: thangData, level: @level, world: @world, supermodel: @supermodel  # supermodel needed for checkForMissingSystems
    @insertSubView @editThangView
    @$el.find('>').hide()
    @editThangView.$el.show()
    Backbone.Mediator.publish 'editor:view-switched', {}

  onLevelThangEdited: (e) ->
    newThang = e.thangData
    @thangsTreema.set "id=#{e.thangID}", newThang

  onLevelThangDoneEditing: (e) ->
    @removeSubView @editThangView
    @editThangView = null
    @onThangsChanged()
    @$el.find('>').show()

  preventDefaultContextMenu: (e) ->
    return unless $(e.target).closest('#canvas-wrapper').length
    e.preventDefault()

  onSpriteContextMenu: (e) ->
    {clientX, clientY} = e.originalEvent.nativeEvent
    if @addThangType
      $('#duplicate a').html 'Stop Duplicate'
    else
      $('#duplicate a').html 'Duplicate'
    $('#contextmenu').css { position: 'fixed', left: clientX, top: clientY }
    $('#contextmenu').show()

  onDeleteClicked: (e) ->
    $('#contextmenu').hide()
    @deleteSelectedExtantThang e

  onDuplicateClicked: (e) ->
    $('#contextmenu').hide()
    @selectAddThangType @selectedExtantThang.spriteName, @selectedExtantThang

  toggleThangsContainer: (e) ->
    $('#all-thangs').toggleClass('hide')

  toggleThangsPalette: (e) ->
    $('#add-thangs-view').toggleClass('hide')

class ThangsNode extends TreemaNode.nodeMap.array
  valueClass: 'treema-array-replacement'
  nodeDescription: 'Thang'

  getTrackedActionDescription: (trackedAction) ->
    trackedActionDescription = super(trackedAction)
    if trackedActionDescription is 'Edit ' + @nodeDescription
      path = trackedAction.path.split '/'
      if path[path.length-1] is 'pos'
        trackedActionDescription = 'Move Thang'
    trackedActionDescription

  getChildren: ->
    children = super(arguments...)
    # TODO: add some filtering to only work with certain types of units at a time
    return children

class ThangNode extends TreemaObjectNode
  valueClass: 'treema-thang'
  collection: false
  @thangNameMap: {}
  @thangKindMap: {}
  buildValueForDisplay: (valEl, data) ->
    pos = _.find(data.components, (c) -> c.config?.pos?)?.config.pos  # TODO: hack
    s = "#{data.thangType}"
    if isObjectID s
      unless name = ThangNode.thangNameMap[s]
        thangType = _.find @settings.supermodel.getModels(ThangType), (m) -> m.get('original') is s
        name = ThangNode.thangNameMap[s] = thangType.get 'name'
      s = name
    s += ' - ' + data.id if data.id isnt s
    if pos
      s += " (#{Math.round(pos.x)}, #{Math.round(pos.y)})"
    else
      s += ' (non-physical)'
    @buildValueForDisplaySimply valEl, s

  onEnterPressed: ->
    Backbone.Mediator.publish 'editor:edit-level-thang', thangID: @getData().id
