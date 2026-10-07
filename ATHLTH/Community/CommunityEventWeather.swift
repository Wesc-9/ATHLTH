import Foundation

struct CommunityEventWeatherSnapshot:
    Equatable
{
    let forecastAt: Date
    let temperatureCelsius: Double
    let apparentTemperatureCelsius: Double?
    let precipitationProbabilityPercent: Int?
    let windSpeedKilometersPerHour: Double?
    let symbolName: String
}

@MainActor
final class CommunityEventWeatherStore:
    ObservableObject
{
    @Published private(set)
    var snapshot:
        CommunityEventWeatherSnapshot?

    @Published private(set)
    var isLoading = false

    @Published private(set)
    var forecastUnavailable = false

    private struct ForecastResponse:
        Decodable
    {
        struct Hourly:
            Decodable
        {
            let time: [Double]
            let temperature: [Double]
            let apparentTemperature: [Double]?
            let weatherCode: [Int]
            let precipitationProbability: [Int]?
            let windSpeed: [Double]?

            enum CodingKeys:
                String,
                CodingKey
            {
                case time
                case temperature =
                    "temperature_2m"
                case apparentTemperature =
                    "apparent_temperature"
                case weatherCode =
                    "weather_code"
                case precipitationProbability =
                    "precipitation_probability"
                case windSpeed =
                    "wind_speed_10m"
            }
        }

        let hourly: Hourly
    }

    func load(
        latitude: Double,
        longitude: Double,
        startsAt: Date
    ) async {
        isLoading = true
        forecastUnavailable = false

        defer {
            isLoading = false
        }

        var components =
            URLComponents(
                string:
                    "https://api.open-meteo.com/v1/forecast"
            )

        components?.queryItems = [
            URLQueryItem(
                name: "latitude",
                value:
                    String(
                        format:
                            "%.5f",
                        latitude
                    )
            ),
            URLQueryItem(
                name: "longitude",
                value:
                    String(
                        format:
                            "%.5f",
                        longitude
                    )
            ),
            URLQueryItem(
                name: "hourly",
                value:
                    [
                        "temperature_2m",
                        "apparent_temperature",
                        "weather_code",
                        "precipitation_probability",
                        "wind_speed_10m"
                    ]
                    .joined(
                        separator: ","
                    )
            ),
            URLQueryItem(
                name: "forecast_days",
                value: "16"
            ),
            URLQueryItem(
                name: "temperature_unit",
                value: "celsius"
            ),
            URLQueryItem(
                name: "wind_speed_unit",
                value: "kmh"
            ),
            URLQueryItem(
                name: "timeformat",
                value: "unixtime"
            ),
            URLQueryItem(
                name: "timezone",
                value: "GMT"
            )
        ]

        guard let url =
                components?.url
        else {
            forecastUnavailable = true
            return
        }

        do {
            let (data, response) =
                try await URLSession.shared
                    .data(from: url)

            guard
                let http =
                    response as?
                    HTTPURLResponse,
                (200..<300)
                    .contains(
                        http.statusCode
                    )
            else {
                forecastUnavailable = true
                return
            }

            let decoded =
                try JSONDecoder()
                    .decode(
                        ForecastResponse.self,
                        from: data
                    )

            guard
                let index =
                    nearestIndex(
                        times:
                            decoded
                                .hourly
                                .time,
                        to:
                            startsAt
                    ),
                index <
                    decoded.hourly
                        .temperature
                        .count,
                index <
                    decoded.hourly
                        .weatherCode
                        .count
            else {
                forecastUnavailable = true
                snapshot = nil
                return
            }

            let forecastDate =
                Date(
                    timeIntervalSince1970:
                        decoded
                            .hourly
                            .time[index]
                )

            guard
                abs(
                    forecastDate
                        .timeIntervalSince(
                            startsAt
                        )
                ) <=
                    2 * 60 * 60
            else {
                forecastUnavailable = true
                snapshot = nil
                return
            }

            snapshot =
                CommunityEventWeatherSnapshot(
                    forecastAt:
                        forecastDate,
                    temperatureCelsius:
                        decoded
                            .hourly
                            .temperature[index],
                    apparentTemperatureCelsius:
                        value(
                            decoded
                                .hourly
                                .apparentTemperature,
                            at: index
                        ),
                    precipitationProbabilityPercent:
                        value(
                            decoded
                                .hourly
                                .precipitationProbability,
                            at: index
                        ),
                    windSpeedKilometersPerHour:
                        value(
                            decoded
                                .hourly
                                .windSpeed,
                            at: index
                        ),
                    symbolName:
                        Self.symbolName(
                            for:
                                decoded
                                    .hourly
                                    .weatherCode[index]
                        )
                )
        } catch {
            snapshot = nil
            forecastUnavailable = true
        }
    }

    private func nearestIndex(
        times: [Double],
        to date: Date
    ) -> Int? {
        guard !times.isEmpty else {
            return nil
        }

        let target =
            date.timeIntervalSince1970

        return times.indices.min {
            lhs,
            rhs in

            abs(
                times[lhs] -
                target
            ) <
            abs(
                times[rhs] -
                target
            )
        }
    }

    private func value<T>(
        _ values: [T]?,
        at index: Int
    ) -> T? {
        guard
            let values,
            values.indices
                .contains(index)
        else {
            return nil
        }

        return values[index]
    }

    private static func symbolName(
        for code: Int
    ) -> String {
        switch code {
        case 0:
            return "sun.max.fill"
        case 1, 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55,
             56, 57:
            return "cloud.drizzle.fill"
        case 61, 63, 65,
             66, 67,
             80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75,
             77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }
}
