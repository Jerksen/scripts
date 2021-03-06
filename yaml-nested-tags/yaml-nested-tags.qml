import QtQml 2.0
import QOwnNotesTypes 1.0

/**
 * Based on the epsilon-notes script from @Maboroshy.
 * After enabling this script internal QOwnNotes tag data will be lost!
 *
 * This script makes QOwnNotes read and write note tags to YAML section before note text.
 * This makes tags independent from the Markdown editor.
 *
 * Nested tags are supported with a custom separator (default '/').
 *
 * The YAML section must start at the first line of the note.
 * YAML format for tags is:
 * ---
 * tags: tag1 multi_word_tag /nested/tag
 * --- or ...
 */

Script {
  property bool debug
  property bool useDashesForClosing
  property string tagHierarchySeparator

  property variant settingsVariables: [{
      "identifier": "useDashesForClosing",
      "name": "",
      "description": "Use three dashes as YAML closer for front matter created by the script",
      "type": "boolean",
      "default": "true",
    },
    {
      "identifier": "tagHierarchySeparator",
      "name": "",
      "description": "Set the separating character for tag hierarchy. \nWarning: '/' is allowed in tag names, so don't use it in tag names or change it to something else.",
      "type": "string",
      "default": "/",
    },
  ]


  function log(txt) {
    debug = true;
    if (debug) {
      script.log("[yaml tags] "+txt);
    }
  }

  /**
   * Fetches the tag hierarchy
   * @param tag
   * @param ancestorsOnly
   */
  function getTagHierarchy(tag, ancestorsOnly = false) {
    var tagHierarchy = tag.name
    if (tag.parentId !== 0) { // better performance
      var tagList = tag.getParentTagNames().reverse();
      if (!ancestorsOnly)
        tagList.push(tag.name)
      tagHierarchy = tagList.join(tagHierarchySeparator)
    } else {
      // root element
      if (ancestorsOnly) {
        return ""
      }
    }
    return tagHierarchy;
  }

  /**
   * Handles note tagging for a note
   *
   * This function is called when tags are added to, removed from or renamed in
   * a note or the tags of a note should be listed
   *
   * @param note
   * @param action can be "add", "remove", "rename" or "list"
   * @param tag to be added, removed or renamed
   * @param newTagName tag name to be renamed to if action = "rename"
   * @return note text string or string-list of tag ids (if action = "list")
   */
  function noteTaggingByObjectHook(note, action, tag, newTagName) {
    var tagHierarchy = getTagHierarchy(tag)

    const noteText = note.noteText
    var noteYaml = null
    var tagLine = null
    var yamlTags = []
    var tagLineStartIndex = 0;
    var tagLineEndIndex = 0;


    let regex_yaml_header = /^[\s]*---[\r\n]{1,2}tags:\s*([\s\S]*)[\r\n]{1,2}(---|\.\.\.)/ // group 1: tags, group 2: yaml ending
    var match = noteText.match(regex_yaml_header)
    if (match) {
      yamlTags = match[1].trim().split(' ')
    }

    switch (action) {
      // adds the tag "tagName" to the note
      // the new note text has to be returned so that the note can be updated
      // returning an empty string indicates that nothing has to be changed
      case 'add':
        tagHierarchy = tagHierarchy.trim()
        tagHierarchy = tagHierarchy.replace(/ /g, '_')
        if (yamlTags.indexOf(tagHierarchy) !== -1)
          return

        yamlTags.push(tagHierarchy)
        yamlTags.sort()
        var yamlCloser = "\n...\n\n"
        if (useDashesForClosing) {
          yamlCloser = '\n---\n\n'
        }
        if (noteYaml === null) {
          return '---\ntags: ' + tagHierarchy + yamlCloser + noteText
        } else if (tagLine === null) {
          return noteText.substring(0, 4) + 'tags: ' + tagHierarchy + '\n' + noteText.substring(4)
        } else {
          return noteText.substring(0, tagLineStartIndex) +
            'tags: ' + yamlTags.join(' ') + noteText.substring(tagLineEndIndex)
        }

        // removes the tag "tagName" from the note
        // the new note text has to be returned so that the note can be updated
        // returning an empty string indicates that nothing has to be changed
      case 'remove':
        tagHierarchy = tagHierarchy.replace(/ /g, '_')


        if (yamlTags.indexOf(tagHierarchy) === -1)
          return

        yamlTags.splice(yamlTags.indexOf(tagHierarchy), 1)
        return noteText.substring(0, tagLineStartIndex) +
          'tags: ' + yamlTags.join(' ') + noteText.substring(tagLineEndIndex);

        // renames the tag "tagName" in the note to "newTagName"
        // the new note text has to be returned so that the note can be updated
        // returning an empty string indicates that nothing has to be changed
      case 'rename':
        var newTagHierarchy = getTagHierarchy(tag, true) // just the ancestor tree
        newTagHierarchy = newTagHierarchy.replace(/ /g, '_')
        tagHierarchy = tagHierarchy.replace(/ /g, '_')
        newTagName = newTagName.replace(/ /g, '_')

        if (newTagHierarchy.length === 0) { // root tag was renamed -> no leading separator needed
          newTagHierarchy = newTagName;
        } else {
          newTagHierarchy += tagHierarchySeparator + newTagName // build the new tag hierarchy
        }

        yamlTags.forEach(function(tags, i, array) {
          if (tags.startsWith(tagHierarchy)) {
            array[i] = array[i].replace(tagHierarchy, newTagHierarchy)
          }
        })


        // tag1 tag2 tag2/subtag/3rdsub2
        // find the old hierarchy and replace it with the new one
        //yamlTags.splice(yamlTags.indexOf(tagHierarchy), 1, newTagHierarchy) // array.splice(start[, deleteCount[, item1[, item2[, ...]]]])
        //yamlTags.push(newTagHierarchy)
        yamlTags.sort()

        return noteText.substring(0, tagLineStartIndex) +
          'tags: ' + yamlTags.join(' ') + noteText.substring(tagLineEndIndex);

        // returns a list of all tag ids of the note
        // animals/mammals/dogs -> returns dogs id
      case 'list':
        var tagIdList = []
        if (yamlTags !== null && yamlTags.length > 0) { // prevent creation of empty tag names ('')
          yamlTags.forEach(function(tagHierarchy, index, array) {
            tagHierarchy = tagHierarchy.replace(/_/g, ' ')
            //tagHierarchy = tagName.split('/').slice(-1) // get the last child of the family
            tag = script.getTagByNameBreadcrumbList(tagHierarchy.split(tagHierarchySeparator)) //  fetches or creates a tag by its "breadcrumb list"
            if (tag.name !== '' && tagIdList.indexOf(tag.id) === -1)
              tagIdList.push(tag.id)
          })
        }
        return tagIdList;
    }

    return ''
  }

  // Exclude YAML from note preview
  function noteToMarkdownHtmlHook(note, html) {

    if (note.noteText.substring(0, 4) === '---\n') {

      // For ---/nYAML/n.../nNote text
      var yamlEndIndex = html.indexOf('\n...\n')

      // For ---/nYAML/n.../n/nNote text
      if (yamlEndIndex === -1)
        yamlEndIndex = html.indexOf('\n...</p>')

      if (yamlEndIndex !== -1)
        return html.substring(yamlEndIndex + 4)

      // For ---/nYAML/n---/nNote text
      return html.replace(/\<hr\/\>(\n|.)*?\<h2 id=\"toc_0\"\>(\n|.)*?\<\/h2\>/, '')
    }
  }


  function init() {
    log("init");
  }
}
