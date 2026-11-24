package app.lawnchair.backup

import java.io.File
import javax.xml.XMLConstants
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element

/**
 * Parses the restored `com.android.launcher3.prefs.xml` before any live
 * mutation. The values are then written through the live [android.content.SharedPreferences]
 * instance so its cache can never write the old state back over the restored
 * file.
 */
object BackupPreferences {
    fun parse(file: File): Map<String, Any> {
        val factory = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = false
            isExpandEntityReferences = false
            runCatching { isXIncludeAware = false }
            disableExternalEntities(this)
        }
        val document = try {
            factory.newDocumentBuilder().parse(file)
        } catch (t: Throwable) {
            throw BackupArchive.ValidationException(
                "The staged preferences XML could not be parsed",
                t,
            )
        }
        val root = document.documentElement
            ?: throw BackupArchive.ValidationException("The staged preferences XML is empty")
        if (root.tagName != "map") {
            throw BackupArchive.ValidationException("The staged preferences XML has no map root")
        }
        val values = linkedMapOf<String, Any>()
        val children = root.childNodes
        for (index in 0 until children.length) {
            val node = children.item(index)
            if (node !is Element) continue
            val name = node.getAttribute("name")
            if (name.isBlank()) {
                throw BackupArchive.ValidationException(
                    "The staged preferences XML has an unnamed value",
                )
            }
            if (name in values) {
                throw BackupArchive.ValidationException(
                    "The staged preferences XML repeats the $name value",
                )
            }
            values[name] = when (node.tagName) {
                "string" -> node.textContent ?: ""
                "int" -> node.requireValue(name).toIntOrNull()
                    ?: throw BackupArchive.ValidationException(
                        "The staged preferences XML has a malformed int $name",
                    )
                "long" -> node.requireValue(name).toLongOrNull()
                    ?: throw BackupArchive.ValidationException(
                        "The staged preferences XML has a malformed long $name",
                    )
                "float" -> node.requireValue(name).toFloatOrNull()
                    ?: throw BackupArchive.ValidationException(
                        "The staged preferences XML has a malformed float $name",
                    )
                "boolean" -> when (node.requireValue(name)) {
                    "true" -> true
                    "false" -> false
                    else -> throw BackupArchive.ValidationException(
                        "The staged preferences XML has a malformed boolean $name",
                    )
                }
                "set" -> parseStringSet(node, name)
                else -> throw BackupArchive.ValidationException(
                    "The staged preferences XML has an unsupported ${node.tagName} value",
                )
            }
        }
        return values
    }

    private fun parseStringSet(node: Element, name: String): Set<String> {
        val values = linkedSetOf<String>()
        val children = node.childNodes
        for (index in 0 until children.length) {
            val child = children.item(index)
            if (child !is Element) continue
            if (child.tagName != "string") {
                throw BackupArchive.ValidationException(
                    "The staged preferences XML has a malformed set $name",
                )
            }
            values += child.textContent ?: ""
        }
        return values
    }

    private fun Element.requireValue(name: String): String =
        getAttribute("value").takeIf { it.isNotBlank() }
            ?: throw BackupArchive.ValidationException(
                "The staged preferences XML is missing the value for $name",
            )

    private fun disableExternalEntities(factory: DocumentBuilderFactory) {
        runCatching { factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true) }
        runCatching {
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
        }
        runCatching {
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false)
        }
        runCatching {
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false)
        }
        runCatching {
            factory.setFeature(
                "http://apache.org/xml/features/nonvalidating/load-external-dtd",
                false,
            )
        }
    }
}
