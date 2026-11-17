import 'names.dart';
import 'profiles.dart';
import 'route_path.dart';

/// Typed registry entry; paths to writable integration files are never user data.
final class ManagedFeature {
  ManagedFeature(this.name, this.state, this.recipe, this.route);

  final DartName name;
  final StateStyle state;
  final Recipe recipe;
  final RoutePath route;

  Map<String, String> toJson() => {
    'name': name.value,
    'state': state.name,
    'recipe': recipe.name,
    'route': route.value,
  };
}
