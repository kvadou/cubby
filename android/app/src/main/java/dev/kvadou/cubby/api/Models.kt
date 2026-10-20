package dev.kvadou.cubby.api

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNamingStrategy
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime

// Shapes returned by the Rails API's family endpoints (api/app/controllers/api/v1/parent).

@Serializable
data class FamilyRef(val id: Int, val name: String, val centerName: String)

@Serializable
data class UserRef(val id: Int, val name: String, val emailAddress: String)

@Serializable
data class TokenResponse(val token: String, val user: UserRef, val families: List<FamilyRef>)

@Serializable
data class FamilyHome(
    val family: Family,
    val center: Center,
    @Serializable(LocalDateSerializer::class) val today: LocalDate,
    val unreadMessages: Int,
    val children: List<Child>,
) {
    @Serializable
    data class Family(val id: Int, val name: String, val guardianName: String)

    @Serializable
    data class Center(val name: String, val city: String, val timezone: String, val directorName: String)

    @Serializable
    data class Child(
        val id: Int,
        val firstName: String,
        val classroom: String? = null,
        val status: String? = null,
        val today: Day? = null,
    )

    @Serializable
    data class Day(
        @Serializable(InstantSerializer::class) val checkedInAt: Instant,
        @Serializable(InstantSerializer::class) val checkedOutAt: Instant? = null,
    )
}

@Serializable
data class AttendanceDay(
    @Serializable(LocalDateSerializer::class) val on: LocalDate,
    val classroom: String,
    @Serializable(InstantSerializer::class) val checkedInAt: Instant,
    @Serializable(InstantSerializer::class) val checkedOutAt: Instant? = null,
)

@Serializable
data class FamilyMessage(
    val id: Int,
    val subject: String,
    val body: String,
    @Serializable(InstantSerializer::class) val sentAt: Instant,
    @Serializable(InstantSerializer::class) val readAt: Instant? = null,
    val from: String,
) {
    val isUnread: Boolean get() = readAt == null
}

@Serializable
data class Invoice(
    val id: Int,
    val number: String,
    val amountCents: Long,
    @Serializable(LocalDateSerializer::class) val periodStart: LocalDate,
    @Serializable(LocalDateSerializer::class) val periodEnd: LocalDate,
    @Serializable(LocalDateSerializer::class) val dueOn: LocalDate,
    val status: String,
    val daysPastDue: Int,
    @Serializable(InstantSerializer::class) val paidAt: Instant? = null,
) {
    val isOpen: Boolean get() = status == "open"
    val isPastDue: Boolean get() = isOpen && daysPastDue > 0
}

@Serializable
internal data class ErrorBody(val error: String? = null, val message: String? = null)

/** snake_case keys, and new fields from the API are ignored rather than crashing an older app. */
@OptIn(ExperimentalSerializationApi::class)
val CubbyJson = Json {
    namingStrategy = JsonNamingStrategy.SnakeCase
    ignoreUnknownKeys = true
    explicitNulls = false
}

/** Rails timestamps carry an offset ("2026-10-19T07:45:00-05:00"). */
object InstantSerializer : KSerializer<Instant> {
    override val descriptor = PrimitiveSerialDescriptor("Instant", PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): Instant = OffsetDateTime.parse(decoder.decodeString()).toInstant()
    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())
}

/** A calendar date with no time or zone ("2026-10-19"), such as an attendance day or a due date. */
object LocalDateSerializer : KSerializer<LocalDate> {
    override val descriptor = PrimitiveSerialDescriptor("LocalDate", PrimitiveKind.STRING)
    override fun deserialize(decoder: Decoder): LocalDate = LocalDate.parse(decoder.decodeString())
    override fun serialize(encoder: Encoder, value: LocalDate) = encoder.encodeString(value.toString())
}
